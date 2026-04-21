import AppKit
import Defaults
import Foundation

enum ClipboardHistoryItemKind: Codable, Hashable {
    case text(String)
    case file(path: String)
}

struct ClipboardHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ClipboardHistoryItemKind
    let copiedAt: Date
    let searchText: String
    let dedupeKey: String

    init(id: UUID = UUID(), kind: ClipboardHistoryItemKind, copiedAt: Date = .now, searchText: String, dedupeKey: String) {
        self.id = id
        self.kind = kind
        self.copiedAt = copiedAt
        self.searchText = searchText
        self.dedupeKey = dedupeKey
    }

    var displayText: String {
        switch kind {
        case let .text(content):
            content
        case let .file(path):
            URL(fileURLWithPath: path).lastPathComponent
        }
    }

    var isFile: Bool {
        if case .file = kind {
            return true
        }

        return false
    }
}

@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var pollTask: Task<Void, Never>?
    private var ignoredNextDedupeKey: String?
    private let maxTextLength = 6_000
    private let maxSearchTextLength = 1_200
    private let activePollingInterval: Duration = .milliseconds(150)
    private let idlePollingInterval: Duration = .milliseconds(750)
    private let hotWindowDuration: Duration = .seconds(10)
    private var hotPollingUntil: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var saveTask: Task<Void, Never>?

    private var maxStoredItems: Int {
        min(max(Defaults[.clipboardHistoryMaxStoredItems], 1), 100)
    }

    private var storageURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clipboard-history.json")
    }

    private init() {
        lastChangeCount = pasteboard.changeCount
        load()
        pruneExpiredItems()
    }

    deinit {
        pollTask?.cancel()
        saveTask?.cancel()
    }

    func startMonitoring() {
        guard Defaults[.enableClipboardHistory] else { return }
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                pollPasteboardIfNeeded()

                let interval = isHotPollingActive ? activePollingInterval : idlePollingInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        saveTask?.cancel()
        saveTask = nil
        hotPollingUntil = nil
    }

    func copy(_ item: ClipboardHistoryItem) {
        ignoredNextDedupeKey = item.dedupeKey
        pasteboard.clearContents()

        switch item.kind {
        case let .text(content):
            pasteboard.setString(content, forType: .string)
        case let .file(path):
            pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
        bumpHotPollingWindow()
    }

    func clear() {
        items = []
        scheduleSave()
    }

    func pruneExpiredItems() {
        let cutoffDate = Date().addingTimeInterval(-Defaults[.clipboardHistoryRetention].timeInterval)
        let nextItems = Array(
            items
                .filter { $0.copiedAt >= cutoffDate }
                .sorted { $0.copiedAt > $1.copiedAt }
                .prefix(maxStoredItems)
        )

        guard nextItems != items else { return }
        items = nextItems
        scheduleSave()
    }

    private var isHotPollingActive: Bool {
        guard let hotPollingUntil else { return false }
        return clock.now < hotPollingUntil
    }

    private func bumpHotPollingWindow() {
        hotPollingUntil = clock.now.advanced(by: hotWindowDuration)
    }

    private func pollPasteboardIfNeeded() {
        guard Defaults[.enableClipboardHistory] else { return }
        guard pasteboard.changeCount != lastChangeCount else {
            pruneExpiredItems()
            return
        }

        lastChangeCount = pasteboard.changeCount
        bumpHotPollingWindow()

        guard let item = readCurrentPasteboardItem() else {
            return
        }

        if ignoredNextDedupeKey == item.dedupeKey {
            ignoredNextDedupeKey = nil
            return
        }

        ignoredNextDedupeKey = nil
        insert(item)
    }

    private func insert(_ item: ClipboardHistoryItem) {
        let cutoffDate = Date().addingTimeInterval(-Defaults[.clipboardHistoryRetention].timeInterval)

        items.removeAll { existingItem in
            existingItem.dedupeKey == item.dedupeKey || existingItem.copiedAt < cutoffDate
        }

        items.insert(item, at: 0)
        items = Array(items.prefix(maxStoredItems))
        scheduleSave()
    }

    private func readCurrentPasteboardItem() -> ClipboardHistoryItem? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            guard urls.count == 1, let url = urls.first, url.isFileURL else {
                return nil
            }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory != true else {
                return nil
            }

            let path = url.path
            return ClipboardHistoryItem(
                kind: .file(path: path),
                searchText: makeFileSearchText(for: path),
                dedupeKey: "file:\(path.standardizedForClipboardSearch)"
            )
        }

        guard let copiedString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !copiedString.isEmpty,
            copiedString.count <= maxTextLength
        else {
            return nil
        }

        let normalizedText = copiedString.standardizedForClipboardSearch

        return ClipboardHistoryItem(
            kind: .text(copiedString),
            searchText: String(normalizedText.prefix(maxSearchTextLength)),
            dedupeKey: "text:\(normalizedText)"
        )
    }

    private func makeFileSearchText(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let joined = "\(fileName) \(path)"
        return String(joined.standardizedForClipboardSearch.prefix(maxSearchTextLength))
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else { return }
        items = decoded.sorted { $0.copiedAt > $1.copiedAt }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items

        saveTask = Task.detached(priority: .utility) { [storageURL] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

private extension String {
    var standardizedForClipboardSearch: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let pieces = folded.split { character in
            !character.isLetter && !character.isNumber
        }

        return pieces.joined(separator: " ")
    }
}

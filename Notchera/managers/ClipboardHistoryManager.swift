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

    init(id: UUID = UUID(), kind: ClipboardHistoryItemKind, copiedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.copiedAt = copiedAt
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
    private var timer: Timer?
    private var ignoredNextItem: ClipboardHistoryItemKind?
    private let maxTextLength = 8_000

    private var maxStoredItems: Int {
        min(max(Defaults[.clipboardHistoryMaxStoredItems], 1), 25)
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
        timer?.invalidate()
    }

    func startMonitoring() {
        guard Defaults[.enableClipboardHistory] else { return }
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ item: ClipboardHistoryItem) {
        ignoredNextItem = item.kind
        pasteboard.clearContents()

        switch item.kind {
        case let .text(content):
            pasteboard.setString(content, forType: .string)
        case let .file(path):
            pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
    }

    func clear() {
        items = []
        save()
    }

    func pruneExpiredItems() {
        let cutoffDate = Date().addingTimeInterval(-Defaults[.clipboardHistoryRetention].timeInterval)
        let prunedItems = items
            .filter { $0.copiedAt >= cutoffDate }
            .sorted { $0.copiedAt > $1.copiedAt }
            .prefix(maxStoredItems)

        let nextItems = Array(prunedItems)
        guard nextItems != items else { return }
        items = nextItems
        save()
    }

    private func pollPasteboard() {
        guard Defaults[.enableClipboardHistory] else { return }
        guard pasteboard.changeCount != lastChangeCount else {
            pruneExpiredItems()
            return
        }

        lastChangeCount = pasteboard.changeCount

        guard let itemKind = readCurrentPasteboardItemKind() else {
            return
        }

        if ignoredNextItem == itemKind {
            ignoredNextItem = nil
            return
        }

        items.insert(ClipboardHistoryItem(kind: itemKind), at: 0)
        items = Array(items.prefix(maxStoredItems))
        pruneExpiredItems()
        save()
    }

    private func readCurrentPasteboardItemKind() -> ClipboardHistoryItemKind? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            guard urls.count == 1, let url = urls.first, url.isFileURL else {
                return nil
            }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory != true else {
                return nil
            }

            return .file(path: url.path)
        }

        guard let copiedString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !copiedString.isEmpty,
            copiedString.count <= maxTextLength
        else {
            return nil
        }

        return .text(copiedString)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else { return }
        items = decoded.sorted { $0.copiedAt > $1.copiedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

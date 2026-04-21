import AppKit
import Foundation

struct AppLauncherItem: Identifiable {
    let id: String
    let displayName: String
    let url: URL
    let icon: NSImage

    fileprivate let normalizedName: String
    fileprivate let normalizedWords: [String]
    fileprivate let acronym: String
    fileprivate let usageKey: String
}

private struct AppLaunchStats: Codable {
    var launchCount: Int = 0
    var lastLaunchedAt: Date?
}

@MainActor
final class AppLauncherManager: ObservableObject {
    static let shared = AppLauncherManager()

    @Published private(set) var items: [AppLauncherItem] = []

    private var hasLoaded = false
    private let searchDirectories = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]
    private var launchStatsByKey: [String: AppLaunchStats] = [:]

    private var storageURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("app-launcher-usage.json")
    }

    private init() {
        loadLaunchStats()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        items = loadItems()
    }

    func filteredItems(for query: String) -> [AppLauncherItem] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return items }

        let rankedItems: [(item: AppLauncherItem, score: Int)] = items.compactMap { item in
            let score = score(item, query: normalizedQuery)
            guard score > 0 else { return nil }
            return (item: item, score: score)
        }

        return rankedItems
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                if lhs.item.displayName.count != rhs.item.displayName.count {
                    return lhs.item.displayName.count < rhs.item.displayName.count
                }

                return lhs.item.displayName.localizedCaseInsensitiveCompare(rhs.item.displayName) == .orderedAscending
            }
            .map(\.item)
    }

    func recordLaunch(for item: AppLauncherItem) {
        var stats = launchStatsByKey[item.usageKey] ?? .init()
        stats.launchCount += 1
        stats.lastLaunchedAt = .now
        launchStatsByKey[item.usageKey] = stats
        saveLaunchStats()
    }

    private func loadItems() -> [AppLauncherItem] {
        var seenPaths = Set<String>()
        var collectedItems: [AppLauncherItem] = []
        let resourceKeys: Set<URLResourceKey> = [.isApplicationKey, .localizedNameKey, .isDirectoryKey]

        for directory in searchDirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
                guard values.isApplication == true else { continue }

                let standardizedPath = url.standardizedFileURL.path
                guard seenPaths.insert(standardizedPath).inserted else { continue }

                let resolvedName = (values.localizedName ?? url.deletingPathExtension().lastPathComponent)
                    .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive, .backwards])
                let normalizedName = normalize(resolvedName)
                let normalizedWords = normalizedName.split(separator: " ").map(String.init)
                let acronym = normalizedWords.compactMap(\.first).map(String.init).joined()
                let icon = NSWorkspace.shared.icon(forFile: standardizedPath)
                let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
                let usageKey = bundleIdentifier.map { "bundle:\($0)" } ?? "path:\(standardizedPath)"
                icon.size = NSSize(width: 64, height: 64)

                collectedItems.append(
                    AppLauncherItem(
                        id: standardizedPath,
                        displayName: resolvedName,
                        url: url,
                        icon: icon,
                        normalizedName: normalizedName,
                        normalizedWords: normalizedWords,
                        acronym: acronym,
                        usageKey: usageKey
                    )
                )
            }
        }

        return collectedItems.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func score(_ item: AppLauncherItem, query: String) -> Int {
        let name = item.normalizedName
        let baseScore: Int

        if name == query {
            baseScore = 10_000 - item.displayName.count
        } else if item.acronym == query {
            baseScore = 9_000 - item.displayName.count
        } else if item.normalizedWords.contains(where: { $0 == query }) {
            baseScore = 8_200 - item.displayName.count
        } else if item.normalizedWords.contains(where: { $0.hasPrefix(query) }) {
            baseScore = 7_600 - item.displayName.count
        } else if name.hasPrefix(query) {
            baseScore = 7_000 - item.displayName.count
        } else if let range = name.range(of: query) {
            let distanceFromStart = name.distance(from: name.startIndex, to: range.lowerBound)
            let boundaryBonus = distanceFromStart == 0 || name[name.index(before: range.lowerBound)] == " " ? 500 : 0
            baseScore = 5_600 - distanceFromStart * 8 + boundaryBonus - item.displayName.count
        } else if let fuzzyScore = fuzzyScore(query: query, candidate: name) {
            baseScore = 3_000 + fuzzyScore - item.displayName.count
        } else {
            return 0
        }

        return baseScore + usageBoost(for: item)
    }

    private func usageBoost(for item: AppLauncherItem) -> Int {
        guard let stats = launchStatsByKey[item.usageKey] else { return 0 }

        let countBoost = min(stats.launchCount * 18, 220)
        let recencyBoost: Int

        if let lastLaunchedAt = stats.lastLaunchedAt {
            let age = Date().timeIntervalSince(lastLaunchedAt)

            switch age {
            case ..<3600:
                recencyBoost = 320
            case ..<86_400:
                recencyBoost = 240
            case ..<604_800:
                recencyBoost = 140
            case ..<2_592_000:
                recencyBoost = 60
            default:
                recencyBoost = 0
            }
        } else {
            recencyBoost = 0
        }

        return min(countBoost + recencyBoost, 420)
    }

    private func fuzzyScore(query: String, candidate: String) -> Int? {
        guard !query.isEmpty, !candidate.isEmpty else { return nil }

        var queryIndex = query.startIndex
        var candidateIndex = candidate.startIndex
        var matchedIndices: [Int] = []
        var candidateOffset = 0

        while queryIndex < query.endIndex, candidateIndex < candidate.endIndex {
            if query[queryIndex] == candidate[candidateIndex] {
                matchedIndices.append(candidateOffset)
                query.formIndex(after: &queryIndex)
            }

            candidate.formIndex(after: &candidateIndex)
            candidateOffset += 1
        }

        guard queryIndex == query.endIndex else { return nil }
        guard let firstMatch = matchedIndices.first else { return nil }

        var score = 0
        var previousIndex: Int?

        for index in matchedIndices {
            score += 14

            if index == 0 {
                score += 24
            } else {
                let previousCharacterIndex = candidate.index(candidate.startIndex, offsetBy: index - 1)
                if candidate[previousCharacterIndex] == " " {
                    score += 18
                }
            }

            if let previousIndex, index == previousIndex + 1 {
                score += 22
            }

            previousIndex = index
        }

        score -= firstMatch * 3
        score -= max(0, candidate.count - query.count)

        return score
    }

    private func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let pieces = folded.split { character in
            !character.isLetter && !character.isNumber
        }

        return pieces.joined(separator: " ")
    }

    private func loadLaunchStats() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: AppLaunchStats].self, from: data) else { return }
        launchStatsByKey = decoded
    }

    private func saveLaunchStats() {
        guard let data = try? JSONEncoder().encode(launchStatsByKey) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

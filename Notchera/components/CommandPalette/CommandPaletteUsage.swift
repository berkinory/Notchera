import Defaults
import SwiftUI

struct ScoredCommandPaletteRow {
    let score: Int
    let row: CommandPaletteRootRow
}

private struct CommandPaletteUsageStats: Codable {
    var useCount: Int = 0
    var lastUsedAt: Date?
}

@MainActor
final class CommandPaletteUsageManager {
    static let shared = CommandPaletteUsageManager()

    private var statsByKey: [String: CommandPaletteUsageStats] = [:]

    private var storageURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("command-palette-usage.json")
    }

    private init() {
        load()
    }

    func recordUse(for usageKey: String) {
        var stats = statsByKey[usageKey] ?? .init()
        stats.useCount += 1
        stats.lastUsedAt = .now
        statsByKey[usageKey] = stats
        save()
    }

    func usageBoost(for usageKey: String) -> Int {
        guard let stats = statsByKey[usageKey] else { return 0 }

        let countBoost = min(stats.useCount * 18, 220)
        let recencyBoost: Int

        if let lastUsedAt = stats.lastUsedAt {
            let age = Date().timeIntervalSince(lastUsedAt)

            switch age {
            case ..<3600:
                recencyBoost = 320
            case ..<86400:
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

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: CommandPaletteUsageStats].self, from: data) else { return }
        statsByKey = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statsByKey) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

import AppKit
import Foundation

struct AppLauncherItem: Identifiable {
    let id: String
    let displayName: String
    let url: URL
    let icon: NSImage
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

    private init() {}

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        items = loadItems()
    }

    func filteredItems(for query: String) -> [AppLauncherItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter {
            $0.displayName.lowercased().contains(normalizedQuery) ||
            $0.url.lastPathComponent.lowercased().contains(normalizedQuery) ||
            $0.url.path.lowercased().contains(normalizedQuery)
        }
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
                let icon = NSWorkspace.shared.icon(forFile: standardizedPath)
                icon.size = NSSize(width: 64, height: 64)

                collectedItems.append(
                    AppLauncherItem(
                        id: standardizedPath,
                        displayName: resolvedName,
                        url: url,
                        icon: icon
                    )
                )
            }
        }

        return collectedItems.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

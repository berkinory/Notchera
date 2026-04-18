import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {
    private static var copiedFileURLs: [URL] = []

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case let .file(bookmark):
            handleBookmarkedFile(bookmark) { url in
                NSWorkspace.shared.open(url)
            }
        case let .link(url):
            NSWorkspace.shared.open(url)
        case let .text(string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case let .file(bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case let .file(bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func copy(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }

        for url in copiedFileURLs {
            url.stopAccessingSecurityScopedResource()
        }
        copiedFileURLs.removeAll()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = []

        for item in items {
            switch item.kind {
            case .file:
                guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else {
                    objects.append(item.displayName as NSString)
                    continue
                }

                if url.startAccessingSecurityScopedResource() {
                    copiedFileURLs.append(url)
                }

                objects.append(url as NSURL)

            case let .text(string):
                objects.append(string as NSString)

            case let .link(url):
                objects.append(url as NSURL)
            }
        }

        if objects.isEmpty {
            pasteboard.setString(items.map(\.displayName).joined(separator: "\n"), forType: .string)
            return
        }

        if !pasteboard.writeObjects(objects) {
            pasteboard.clearContents()
            pasteboard.setString(items.map(\.displayName).joined(separator: "\n"), forType: .string)
        }
    }

    static func copyAll() {
        copy(ShelfStateViewModel.shared.items)
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    static func removeAll() {
        ShelfStateViewModel.shared.clear()
        ShelfSelectionModel.shared.clear()
    }

    private static func handleBookmarkedFile(_ bookmarkData: Data, action: @escaping @Sendable (URL) -> Void) {
        Task {
            let bookmark = Bookmark(data: bookmarkData)
            if let url = bookmark.resolveURL() {
                url.accessSecurityScopedResource { accessibleURL in
                    action(accessibleURL)
                }
            }
        }
    }
}

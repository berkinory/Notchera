import AppKit
import Foundation

enum ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }

    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL(),
           let bookmark = createBookmark(for: actualFileURL)
        {
            return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
        }

        if let fileURL = await provider.extractItem(),
           let bookmark = createBookmark(for: fileURL)
        {
            return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
        }

        return nil
    }

    private static func createBookmark(for url: URL) -> Data? {
        (try? Bookmark(url: url))?.data
    }
}

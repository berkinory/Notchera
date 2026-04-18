import AppKit
import CoreGraphics

extension NSScreen {
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    @MainActor static func screen(withUUID uuid: String) -> NSScreen? {
        NSScreenUUIDCache.shared.screen(forUUID: uuid)
    }

    @MainActor static var screensByUUID: [String: NSScreen] {
        NSScreenUUIDCache.shared.allScreens
    }
}

/// Cache for UUID to NSScreen mappings to avoid repeated lookups
@MainActor
final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()

    private var cache: [String: NSScreen] = [:]
    private var observer: Any?

    private init() {
        rebuildCache()
        setupObserver()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildCache()
        }
    }

    private func rebuildCache() {
        var newCache: [String: NSScreen] = [:]

        for screen in NSScreen.screens {
            if let uuid = screen.displayUUID {
                newCache[uuid] = screen
            }
        }

        cache = newCache
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        cache[uuid]
    }

    var allScreens: [String: NSScreen] {
        cache
    }
}

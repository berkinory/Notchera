import Cocoa
import UniformTypeIdentifiers

final class DragDetector {


    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }




    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string,
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    func startMonitoring() {
        stopMonitoring()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            pasteboardChangeCount = dragPasteboard.changeCount
            isDragging = true
            isContentDragging = false
            hasEnteredNotchRegion = false
        }

        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            guard isDragging else { return }

            let newContent = dragPasteboard.changeCount != pasteboardChangeCount

            if newContent, !isContentDragging, hasValidDragContent() {
                isContentDragging = true
            }

            if isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                onDragMove?(mouseLocation)

                let containsMouse = notchRegion.contains(mouseLocation)
                if containsMouse, !hasEnteredNotchRegion {
                    hasEnteredNotchRegion = true
                    onDragEntersNotchRegion?()
                } else if !containsMouse, hasEnteredNotchRegion {
                    hasEnteredNotchRegion = false
                    onDragExitsNotchRegion?()
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            guard isDragging else { return }

            isDragging = false
            isContentDragging = false
            hasEnteredNotchRegion = false
            pasteboardChangeCount = -1
        }
    }

    func stopMonitoring() {
        for monitor in [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}

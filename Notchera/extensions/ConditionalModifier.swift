import AppKit
import SwiftUI

private final class ArrowCursorNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseMoved],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with _: NSEvent) {
        NSCursor.arrow.set()
    }
}

private struct ArrowCursorRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> ArrowCursorNSView {
        ArrowCursorNSView()
    }

    func updateNSView(_ nsView: ArrowCursorNSView, context _: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

extension View {
    @ViewBuilder func conditionalModifier(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func forceArrowCursor() -> some View {
        overlay {
            ArrowCursorRegion()
        }
    }
}

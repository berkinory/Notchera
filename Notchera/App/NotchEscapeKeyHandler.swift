import AppKit
import SwiftUI

struct NotchEscapeKeyHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> EscapeMonitorHostView {
        let view = EscapeMonitorHostView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_: EscapeMonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_: EscapeMonitorHostView, coordinator: Coordinator) {
        coordinator.stop()
    }
}

final class EscapeMonitorHostView: NSView {}

extension NotchEscapeKeyHandler {
    final class Coordinator {
        var isEnabled: Bool
        var onEscape: () -> Void

        private var monitor: Any?

        init(isEnabled: Bool, onEscape: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEscape = onEscape
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, isEnabled else { return event }
                guard Int(event.keyCode) == 53 else { return event }
                onEscape()
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

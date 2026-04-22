import AppKit
import SwiftUI

struct TrackpadTabSwitchRegion: NSViewRepresentable {
    let isEnabled: Bool
    let shouldHandle: () -> Bool
    let onHorizontalSwipe: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            shouldHandle: shouldHandle,
            onHorizontalSwipe: onHorizontalSwipe
        )
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.coordinator = context.coordinator
        context.coordinator.start()
        return view
    }

    func updateNSView(_: MonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.shouldHandle = shouldHandle
        context.coordinator.onHorizontalSwipe = onHorizontalSwipe
    }

    static func dismantleNSView(_: MonitorHostView, coordinator: Coordinator) {
        coordinator.stop()
    }
}

final class MonitorHostView: NSView {
    weak var coordinator: TrackpadTabSwitchRegion.Coordinator?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

extension TrackpadTabSwitchRegion {
    final class Coordinator {
        var isEnabled: Bool
        var shouldHandle: () -> Bool
        var onHorizontalSwipe: (CGFloat) -> Void

        private var monitor: Any?
        private var accumulatedHorizontalDelta: CGFloat = 0
        private var didTriggerForCurrentGesture = false
        private var fallbackResetWorkItem: DispatchWorkItem?

        private let swipeThreshold: CGFloat = 42
        private let horizontalDominanceRatio: CGFloat = 1.15
        private let fallbackResetDelay: TimeInterval = 0.45

        init(
            isEnabled: Bool,
            shouldHandle: @escaping () -> Bool,
            onHorizontalSwipe: @escaping (CGFloat) -> Void
        ) {
            self.isEnabled = isEnabled
            self.shouldHandle = shouldHandle
            self.onHorizontalSwipe = onHorizontalSwipe
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            fallbackResetWorkItem?.cancel()
            fallbackResetWorkItem = nil

            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            resetGesture()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  event.hasPreciseScrollingDeltas,
                  shouldHandle()
            else {
                resetGesture()
                return event
            }

            if event.phase.contains(.began) {
                resetGesture()
            }

            scheduleFallbackReset()

            if didTriggerForCurrentGesture {
                if isMomentumTerminal(event) || event.phase.contains(.cancelled) {
                    resetGesture()
                }

                return nil
            }

            if isPhaseTerminalWithoutMomentum(event) {
                resetGesture()
                return event
            }

            let horizontalDelta = event.scrollingDeltaX
            let verticalDelta = event.scrollingDeltaY

            guard abs(horizontalDelta) > abs(verticalDelta) * horizontalDominanceRatio else {
                return event
            }

            accumulatedHorizontalDelta += horizontalDelta

            guard abs(accumulatedHorizontalDelta) >= swipeThreshold else {
                return nil
            }

            didTriggerForCurrentGesture = true
            onHorizontalSwipe(accumulatedHorizontalDelta)
            return nil
        }

        private func scheduleFallbackReset() {
            fallbackResetWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.resetGesture()
            }

            fallbackResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackResetDelay, execute: workItem)
        }

        private func isMomentumTerminal(_ event: NSEvent) -> Bool {
            event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
        }

        private func isPhaseTerminalWithoutMomentum(_ event: NSEvent) -> Bool {
            (event.phase.contains(.ended) || event.phase.contains(.cancelled)) && event.momentumPhase.isEmpty
        }

        private func resetGesture() {
            fallbackResetWorkItem?.cancel()
            fallbackResetWorkItem = nil
            accumulatedHorizontalDelta = 0
            didTriggerForCurrentGesture = false
        }
    }
}

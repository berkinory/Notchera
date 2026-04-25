import AppKit
import Defaults
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: AppUpdaterController?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        setupWindow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUpdaterController(_ controller: AppUpdaterController) {
        updaterController = controller
        setupWindow()
    }

    private func setupWindow() {
        guard let window else { return }

        window.title = "Notchera Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor.windowBackgroundColor

        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]

        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false

        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("NotcheraSettingsWindow")

        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        updateTrafficLightLayout()

        window.delegate = self
    }

    private func updateTrafficLightLayout() {
        guard let window else { return }

        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        guard let closeButton = buttons.first else { return }

        let origin = NSPoint(x: 16, y: closeButton.frame.origin.y)
        let spacing: CGFloat = 6

        for (index, button) in buttons.enumerated() {
            var frame = button.frame
            frame.origin.x = origin.x + CGFloat(index) * (frame.width + spacing)
            frame.origin.y = origin.y
            button.setFrameOrigin(frame.origin)
        }
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)

        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }

        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            self?.updateTrafficLightLayout()
        }
    }

    override func close() {
        super.close()
        relinquishFocus()
    }

    private func relinquishFocus() {
        window?.orderOut(nil)

        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        relinquishFocus()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowDidBecomeKey(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        updateTrafficLightLayout()
    }

    func windowDidResize(_: Notification) {
        updateTrafficLightLayout()
    }

    func windowDidResignKey(_: Notification) {}
}

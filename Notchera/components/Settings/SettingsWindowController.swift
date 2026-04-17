import AppKit
import Defaults
import Sparkle
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
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

    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        updaterController = controller
        setupWindow()
    }

    private func setupWindow() {
        guard let window else { return }

        window.title = "Notchera Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true

        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]

        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false

        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("NotcheraSettingsWindow")

        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView

        window.delegate = self
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
    }

    func windowDidResignKey(_: Notification) {}
}

import ApplicationServices
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        MenuBarExtra("notchera", systemImage: "square.fill", isInserted: $showMenuBarIcon) {
            Text("Notchera \(Bundle.main.releaseVersionNumberPretty)")
                .foregroundStyle(.secondary)

            Divider()

            Button {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(self)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
    }
}

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Command Palette:", name: .commandPalette)
                KeyboardShortcuts.Recorder("Open Clipboard Manager:", name: .clipboardHistoryPanel)
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

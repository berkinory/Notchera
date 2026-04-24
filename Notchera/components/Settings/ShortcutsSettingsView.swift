import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct ShortcutsSettingsView: View {
    @Default(.enableCommandLauncher) private var enableCommandLauncher
    @Default(.enableClipboardHistory) private var enableClipboardHistory

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch", name: .toggleNotchOpen)
                KeyboardShortcuts.Recorder("Launcher", name: .commandPalette)
                    .disabled(!enableCommandLauncher)
                KeyboardShortcuts.Recorder("Clipboard History", name: .clipboardHistoryPanel)
                    .disabled(!enableClipboardHistory)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

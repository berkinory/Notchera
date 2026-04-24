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
                KeyboardShortcuts.Recorder("Open Launcher:", name: .commandPalette)
                    .disabled(!enableCommandLauncher)
                KeyboardShortcuts.Recorder("Open Clipboard Manager:", name: .clipboardHistoryPanel)
                    .disabled(!enableClipboardHistory)
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

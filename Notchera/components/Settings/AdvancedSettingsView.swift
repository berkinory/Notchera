import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct AdvancedSettingsView: View {
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.lockScreenPlayerStyle) var lockScreenPlayerStyle
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    @Default(.hideNotchInFullscreen) var hideNotchInFullscreen

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideNotchInFullscreen) {
                    Text("Hide notch in fullscreen")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                if showOnLockScreen {
                    Picker("Lock screen player style", selection: $lockScreenPlayerStyle) {
                        ForEach(LockScreenPlayerStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

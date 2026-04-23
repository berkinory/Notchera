import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct AppearanceSettingsView: View {
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .matchAlbumArtColor) {
                    Text("Match album art color")
                }
            } header: {
                Text("Media")
            }
        }
        .scrollContentBackground(.hidden)
    }
}

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct ShelfSettingsView: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .notchShelf) {
                    Text("Enable shelf")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }

            }
        }
        .scrollContentBackground(.hidden)
    }
}

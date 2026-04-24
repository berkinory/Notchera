import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
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

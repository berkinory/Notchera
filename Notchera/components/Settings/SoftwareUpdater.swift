import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater

        checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyUpdatesApp: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticallyUpdatesApp = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        Section {
            Toggle("Automatically update the app", isOn: $automaticallyUpdatesApp)
                .onChange(of: automaticallyUpdatesApp) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                    updater.automaticallyDownloadsUpdates = newValue
                }
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}

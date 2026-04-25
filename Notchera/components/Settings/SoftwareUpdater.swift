import SwiftUI

#if canImport(Sparkle)
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: AppUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: AppUpdater

    init(updater: AppUpdater) {
        self.updater = updater
        checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    private let updater: AppUpdater

    @State private var automaticallyUpdatesApp: Bool

    init(updater: AppUpdater) {
        self.updater = updater
        automaticallyUpdatesApp = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically download and install updates", isOn: $automaticallyUpdatesApp)
                    .onChange(of: automaticallyUpdatesApp) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                        updater.automaticallyDownloadsUpdates = newValue
                    }

                CheckForUpdatesView(updater: updater)
            }
            .padding(.vertical, 2)
        } header: {
            SettingsSectionHeader(title: "Software updates")
        }
    }
}
#else
struct UpdaterSettingsView: View {
    var body: some View {
        EmptyView()
    }
}
#endif

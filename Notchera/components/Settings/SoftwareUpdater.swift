import SwiftUI

private let brewUpgradeCommand = "brew update && brew upgrade --cask notchera"

struct BrewUpdaterSettingsView: View {
    @State private var isCheckingForUpdates = false
    @State private var updateResult: BrewUpdateCheckResult?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Button(isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                    Task {
                        isCheckingForUpdates = true
                        defer { isCheckingForUpdates = false }

                        do {
                            errorMessage = nil
                            updateResult = try await BrewUpdateChecker.check()
                        } catch {
                            updateResult = nil
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(isCheckingForUpdates)

                if let updateResult {
                    if updateResult.updateAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Version \(updateResult.latestVersion) is available.")
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Text(brewUpgradeCommand)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)

                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(brewUpgradeCommand, forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else {
                        Text("You’re up to date.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 2)
        } header: {
            SettingsSectionHeader(title: "Software updates")
        }
    }
}

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

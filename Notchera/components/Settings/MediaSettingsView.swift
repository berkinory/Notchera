import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct MediaSettingsView: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @Default(.enableLyrics) var enableLyrics
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                HStack {
                    Stepper(value: $waitInterval, in: 0 ... 10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }

            Section {
                MusicSlotConfigurationView()
                Toggle(isOn: $enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
                .onChange(of: enableLyrics) { _, isEnabled in
                    MusicManager.shared.setLyricsEnabled(isEnabled)
                }
            } header: {
                Text("Media controls")
            } footer: {
                Text("Customize which controls appear in the music player.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            MediaControllerType.allCases
        }
    }
}

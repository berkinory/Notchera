import Defaults
import SwiftUI

struct MediaSettingsView: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @Default(.enableLyrics) var enableLyrics
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    ForEach(selectableMediaControllers) { controller in
                        MediaSourceOptionCard(
                            controller: controller,
                            isSelected: mediaController == controller,
                            action: {
                                mediaController = controller
                                NotificationCenter.default.post(
                                    name: Notification.Name.mediaControllerChanged,
                                    object: nil
                                )
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            } header: {
                SettingsSectionHeader(title: "Source")
            }

            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )

                if coordinator.musicLiveActivityEnabled {
                    SettingsSliderRow(
                        title: "Media inactivity timeout",
                        value: $waitInterval,
                        range: 0 ... 10,
                        step: 1,
                        formatValue: { value in
                            String(format: "%.0fs", value)
                        }
                    )
                }
            } header: {
                SettingsSectionHeader(title: "Live Activity")
            }

            Section {
                MusicSlotConfigurationView()
                Toggle("Show lyrics", isOn: $enableLyrics)
                    .onChange(of: enableLyrics) { _, isEnabled in
                        MusicManager.shared.setLyricsEnabled(isEnabled)
                    }
            } header: {
                SettingsSectionHeader(title: "Media controls")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var selectableMediaControllers: [MediaControllerType] {
        [.automatic, .spotify, .appleMusic, .youtubeMusic]
    }
}

private struct MediaSourceOptionCard: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        SettingsOptionCard(title: title, isSelected: isSelected, action: action) {
            icon
        }
    }

    private var title: String {
        switch controller {
        case .automatic:
            "Automatic"
        case .spotify:
            "Spotify"
        case .appleMusic:
            "Apple Music"
        case .youtubeMusic:
            "YT Music"
        case .nowPlaying:
            "Now Playing"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch controller {
        case .automatic:
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        case .spotify:
            Image("spotify")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 24, height: 24)
        case .appleMusic:
            Image("apple-music")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 24, height: 24)
        case .youtubeMusic:
            Image("youtube-music")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 24, height: 24)
        case .nowPlaying:
            Image(systemName: "play.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

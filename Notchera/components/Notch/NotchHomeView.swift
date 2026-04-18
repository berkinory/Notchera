import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    let albumArtNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .bottom, spacing: 10) {
                AlbumArtView(albumArtNamespace: albumArtNamespace)
                    .frame(width: 52, height: 52)

                MusicControlsView(albumArtNamespace: albumArtNamespace)
            }
            .padding(.top, 2)
            .padding(.horizontal, 5)

            MusicSliderRowView()
                .padding(.horizontal, 7)

            MusicToolbarRowView()
                .padding(.horizontal, 7)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                albumArtImage
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 8)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened
                )
            )
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    let albumArtNamespace: Namespace.ID

    var body: some View {
        GeometryReader { geo in
            songInfo(width: geo.size.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 30)
        .buttonStyle(PlainButtonStyle())
    }

    private func songInfo(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(
                    $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                    frameWidth: max(0, width - 44)
                )
                MarqueeText(
                    $musicManager.artistName,
                    font: .headline,
                    nsFont: .headline,
                    textColor: matchAlbumArtColor
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                        : .gray,
                    frameWidth: max(0, width - 44)
                )
                .fontWeight(.regular)
                if false, Defaults[.enableLyrics] {
                    TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                        let currentElapsed: Double = {
                            guard musicManager.isPlaying else { return musicManager.elapsedTime }
                            let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                            let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                            return min(max(progressed, 0), musicManager.songDuration)
                        }()
                        let line: String = {
                            if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                            if !musicManager.syncedLyrics.isEmpty {
                                return musicManager.lyricLine(at: currentElapsed)
                            }
                            let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                        }()
                        let isPersian = line.unicodeScalars.contains { scalar in
                            let v = scalar.value
                            return v >= 0x0600 && v <= 0x06FF
                        }
                        MarqueeText(
                            .constant(line),
                            font: .subheadline,
                            nsFont: .subheadline,
                            textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                            frameWidth: max(0, width - 36)
                        )
                        .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                        .lineLimit(1)
                        .opacity(musicManager.isPlaying ? 1 : 0)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            Spacer(minLength: 0)

            MusicSpectrumIndicatorView(
                albumArtNamespace: albumArtNamespace,
                barWidth: 68,
                spectrumSize: CGSize(width: 26, height: 16),
                containerSize: CGSize(width: 28, height: 24),
                cornerRadius: 8
            )
        }
        .frame(height: 30, alignment: .bottom)
    }
}

struct MusicSliderRowView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 4)
            .frame(height: 24)
        }
    }
}

struct MusicToolbarRowView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: NotcheraViewModel
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        return Array(padded.prefix(sanitizedLimit))
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            "repeat"
        case .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            .primary
        case .all, .one:
            .red
        }
    }
}

struct MusicSpectrumIndicatorView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    let albumArtNamespace: Namespace.ID
    let barWidth: CGFloat
    let spectrumSize: CGSize
    let containerSize: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    matchAlbumArtColor
                        ? Color(nsColor: musicManager.avgColor).gradient
                        : Color.white.gradient
                )
                .frame(width: barWidth, alignment: .center)
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        .frame(width: spectrumSize.width, height: spectrumSize.height)
                }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
        .opacity(musicManager.isPlaying ? 1 : 0.55)
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension [MusicControlButton] {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = .distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider, musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0 ... 1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {}
    }

    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            "speaker.slash"
        } else if volumeSliderValue == 0 {
            "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            "speaker.2.fill"
        } else {
            "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity)
    }

    private var mainContent: some View {
        MusicPlayerView(albumArtNamespace: albumArtNamespace)
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            .blur(radius: vm.notchState == .closed ? 2 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            timeLabel(timeString(from: sliderValue), alignment: .leading)

            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: Defaults[.matchAlbumArtColor]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
                    : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            timeLabel(timeString(from: duration), alignment: .trailing)
        }
        .fontWeight(.medium)
        .foregroundColor(.gray.opacity(0.72))
        .font(.caption)
        .onChange(of: currentDate) {
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    private var timeLabelTemplate: String {
        timeString(from: max(duration, sliderValue))
    }

    @ViewBuilder
    private func timeLabel(_ value: String, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Text(timeLabelTemplate)
                .hidden()

            Text(value)
        }
        .monospacedDigit()
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 10 : 6)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}

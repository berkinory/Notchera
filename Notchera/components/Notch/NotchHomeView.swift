import Combine
import Defaults
import SwiftUI

private extension VerticalAlignment {
    private enum MusicTitleRowAlignment: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let musicTitleRow = VerticalAlignment(MusicTitleRowAlignment.self)
}

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
            .scaleEffect(musicManager.isPlaying ? 1 : 0.92)

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.45)
            .blur(radius: 5)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened,
                    style: .continuous
                )
            )
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    @Default(.enableLyrics) private var enableLyrics
    let albumArtNamespace: Namespace.ID

    private let controlHeight: CGFloat = 52
    private let lyricRowHeight: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: showsSyncedLyrics && musicManager.playbackRate > 0 ? 0.25 : nil)) { timeline in
                songInfo(width: geo.size.width, currentDate: timeline.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: controlHeight)
        .buttonStyle(PlainButtonStyle())
    }

    private var showsSyncedLyrics: Bool {
        enableLyrics && !musicManager.isFetchingLyrics && !musicManager.syncedLyrics.isEmpty
    }

    private func songInfo(width: CGFloat, currentDate: Date? = nil) -> some View {
        HStack(alignment: .musicTitleRow, spacing: 6) {
            metadataView(width: width, currentDate: currentDate)

            Spacer(minLength: 0)

            MusicSpectrumIndicatorView(
                albumArtNamespace: albumArtNamespace,
                isPlaying: musicManager.isPlaying,
                avgColor: musicManager.avgColor,
                barWidth: 54,
                spectrumSize: CGSize(width: 16, height: 12),
                containerSize: CGSize(width: 24, height: 22),
                cornerRadius: 8
            )
            .alignmentGuide(.musicTitleRow) { dimensions in
                dimensions[VerticalAlignment.center]
            }
        }
        .frame(height: controlHeight, alignment: .bottom)
    }

    private func metadataView(width: CGFloat, currentDate: Date?) -> some View {
        let metadataWidth = max(0, width - 36)

        return ZStack(alignment: .topLeading) {
            if showsSyncedLyrics, let currentDate {
                syncedLyricLineView(width: metadataWidth, currentDate: currentDate)
                    .transition(lyricLineTransition)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                titleView(width: metadataWidth)
                artistView(width: metadataWidth)
            }
        }
        .frame(width: metadataWidth, height: controlHeight, alignment: .bottomLeading)
        .clipped()
        .animation(.smooth(duration: 0.22), value: showsSyncedLyrics)
    }

    private func titleView(width: CGFloat) -> some View {
        MarqueeText(
            $musicManager.songTitle,
            font: .headline,
            nsFont: .headline,
            textColor: .white,
            frameWidth: width
        )
        .fontWeight(.medium)
        .alignmentGuide(.musicTitleRow) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }

    private func artistView(width: CGFloat) -> some View {
        MarqueeText(
            $musicManager.artistName,
            font: .headline,
            nsFont: .headline,
            textColor: matchAlbumArtColor
                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                : .gray,
            frameWidth: width
        )
        .fontWeight(.regular)
    }

    private func syncedLyricLineView(width: CGFloat, currentDate: Date) -> some View {
        let currentElapsed = currentPlaybackElapsed(at: currentDate)
        let line = musicManager.lyricLine(at: currentElapsed)

        return ZStack(alignment: .leading) {
            MarqueeText(
                .constant(line),
                font: lyricLineFont(for: line),
                nsFont: .subheadline,
                textColor: .white.opacity(0.34),
                minDuration: 0.8,
                frameWidth: width
            )
            .id(line)
            .transition(lyricLineTransition)
        }
        .frame(height: lyricRowHeight, alignment: .leading)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .animation(.smooth(duration: 0.2), value: line)
    }

    private var lyricLineTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 2)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .leading)),
            removal: .offset(y: -2)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .leading))
        )
    }

    private func currentPlaybackElapsed(at currentDate: Date) -> Double {
        guard musicManager.isPlaying else { return musicManager.elapsedTime }
        let delta = currentDate.timeIntervalSince(musicManager.timestampDate)
        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
        return min(max(progressed, 0), musicManager.songDuration)
    }

    private func lyricLineFont(for text: String) -> Font {
        if text.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF }) {
            return .custom("Vazirmatn-Regular", size: 10.25)
        }

        return .system(size: 10.25, weight: .medium)
    }
}

struct MusicSliderRowView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    init() {
        _sliderValue = State(initialValue: MusicManager.shared.estimatedPlaybackPosition())
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.2 : nil)) { timeline in
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
        .onAppear {
            syncSliderValue()
        }
        .onChange(of: musicManager.elapsedTime) {
            syncSliderValue()
        }
        .onChange(of: musicManager.songDuration) {
            syncSliderValue()
        }
        .onChange(of: musicManager.timestampDate) {
            syncSliderValue()
        }
    }

    private func syncSliderValue() {
        guard !dragging, musicManager.timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
        sliderValue = min(musicManager.estimatedPlaybackPosition(), musicManager.songDuration)
    }
}

struct MusicToolbarRowView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: NotcheraViewModel
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    @Default(.enableLyrics) private var enableLyrics

    private let slotWidth: CGFloat = 40

    var body: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
                    .frame(width: slotWidth, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.defaultLayout.count),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        return Array(padded.prefix(sanitizedLimit))
    }

    private var activeControlColor: Color {
        matchAlbumArtColor
            ? Color(nsColor: musicManager.avgColor)
            : .white
    }

    private var activeToggleBackgroundColor: Color {
        activeControlColor.opacity(matchAlbumArtColor ? 0.18 : 0.14)
    }

    private var inactiveControlColor: Color {
        .secondary.opacity(0.5)
    }

    private var inactiveToggleBackgroundColor: Color {
        Color.white.opacity(0.04)
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? activeControlColor : inactiveControlColor,
                backgroundColor: musicManager.isShuffled ? activeToggleBackgroundColor : inactiveToggleBackgroundColor,
                scale: .medium,
                tapEffect: .rotateCounterClockwise
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .lyrics:
            HoverButton(
                icon: "quote.bubble",
                iconColor: enableLyrics ? activeControlColor : inactiveControlColor,
                backgroundColor: enableLyrics ? activeToggleBackgroundColor : inactiveToggleBackgroundColor,
                scale: .medium,
                tapEffect: .bounce
            ) {
                let nextValue = !enableLyrics
                enableLyrics = nextValue
                MusicManager.shared.setLyricsEnabled(nextValue)
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium, tapEffect: .nudgeLeft) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            OptimisticPlayPauseButton()
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium, tapEffect: .nudgeRight) {
                MusicManager.shared.nextTrack()
            }
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium, tapEffect: .rotateCounterClockwise) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium, tapEffect: .rotateClockwise) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(width: slotWidth, height: 1)
        }
    }

}

struct OptimisticPlayPauseButton: View {
    @ObservedObject private var musicManager = MusicManager.shared

    @State private var isHovering = false
    @State private var optimisticIsPlaying: Bool?
    @State private var optimisticGeneration = 0

    private let size: CGFloat = 40
    private var cornerRadius: CGFloat { size * 0.28 }

    private var displayedIsPlaying: Bool {
        optimisticIsPlaying ?? musicManager.isPlaying
    }

    private var iconName: String {
        displayedIsPlaying ? "pause.fill" : "play.fill"
    }

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: iconName)
                        .foregroundColor(.primary)
                        .font(.largeTitle)
                        .contentTransition(.symbolEffect(.replace))
                }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.smooth(duration: 0.14), value: displayedIsPlaying)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.22)) {
                isHovering = hovering
            }
        }
        .onChange(of: musicManager.isPlaying) { _, _ in
            withAnimation(.smooth(duration: 0.12)) {
                optimisticIsPlaying = nil
            }
        }
    }

    private func togglePlayback() {
        let targetState = !displayedIsPlaying
        optimisticGeneration += 1
        let currentGeneration = optimisticGeneration

        withAnimation(.smooth(duration: 0.12)) {
            optimisticIsPlaying = targetState
        }

        MusicManager.shared.togglePlay()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))

            guard optimisticGeneration == currentGeneration else { return }
            guard optimisticIsPlaying == targetState else { return }
            guard musicManager.isPlaying != targetState else { return }

            withAnimation(.smooth(duration: 0.12)) {
                optimisticIsPlaying = nil
            }
        }
    }
}

struct MusicSpectrumIndicatorView: View {
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    let albumArtNamespace: Namespace.ID
    let isPlaying: Bool
    let avgColor: NSColor
    let barWidth: CGFloat
    let spectrumSize: CGSize
    let containerSize: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    matchAlbumArtColor
                        ? Color(nsColor: avgColor).gradient
                        : Color.white.gradient
                )
                .frame(width: barWidth, alignment: .center)
                .mask {
                    AudioSpectrumView(isPlaying: isPlaying)
                        .frame(width: spectrumSize.width, height: spectrumSize.height)
                }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
        .opacity(isPlaying ? 1 : 0.55)
    }
}

private extension [MusicControlButton] {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
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
        .onAppear {
            syncSliderValue(at: currentDate)
        }
        .onChange(of: currentDate) {
            syncSliderValue(at: currentDate)
        }
        .onChange(of: elapsedTime) {
            syncSliderValue(at: currentDate)
        }
        .onChange(of: duration) {
            syncSliderValue(at: currentDate)
        }
        .onChange(of: timestampDate) {
            syncSliderValue(at: currentDate)
        }
    }

    private func syncSliderValue(at date: Date) {
        guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
        sliderValue = min(MusicManager.shared.estimatedPlaybackPosition(at: date), duration)
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
        .offset(y: 1)
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
            let width = max(geometry.size.width, 1)
            let height = CGFloat(dragging ? 8 : 6)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = min(max(rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan, 0), 1)
            let filledTrackWidth = progress * width
            let visibleFilledTrackWidth = progress == 0 ? 0 : max(filledTrackWidth, height)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: visibleFilledTrackWidth, height: height)
                    .opacity(progress == 0 ? 0 : 1)
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .animation(dragging ? nil : .linear(duration: 0.12), value: value)
            .animation(.easeOut(duration: 0.08), value: dragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging {
                            dragging = true
                        }

                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        lastDragged = Date()
                        onValueChange?(value)
                        dragging = false
                    }
            )
        }
    }
}

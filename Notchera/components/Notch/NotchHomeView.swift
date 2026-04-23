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

private struct HorizontalBlurFadeTransitionModifier: ViewModifier {
    let xOffset: CGFloat
    let blurRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: xOffset)
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func horizontalBlurFade(insertionX: CGFloat, removalX: CGFloat, blur: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: HorizontalBlurFadeTransitionModifier(xOffset: insertionX, blurRadius: blur, opacity: 0),
                identity: HorizontalBlurFadeTransitionModifier(xOffset: 0, blurRadius: 0, opacity: 1)
            ),
            removal: .modifier(
                active: HorizontalBlurFadeTransitionModifier(xOffset: removalX, blurRadius: blur, opacity: 0),
                identity: HorizontalBlurFadeTransitionModifier(xOffset: 0, blurRadius: 0, opacity: 1)
            )
        )
    }
}

// MARK: - Music Player Components

struct MusicPlayerView: View {
    let albumArtNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .bottom, spacing: 10) {
                AlbumArtView(albumArtNamespace: albumArtNamespace)
                    .frame(width: 64, height: 64)

                MusicControlsView(albumArtNamespace: albumArtNamespace)
            }
            .padding(.top, 4)
            .padding(.horizontal, 5)

            MusicSliderRowView()
                .padding(.horizontal, 7)

            MusicToolbarRowView()
                .padding(.horizontal, 7)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct FlippingAlbumArtCard: View {
    @ObservedObject private var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    let cornerRadius: CGFloat
    let hoverTilt: CGSize
    let isHovering: Bool

    private let artworkRevealProgressThreshold = 0.68

    private var flipProgress: Double {
        musicManager.isFlipping ? musicManager.flipProgress : 0
    }

    private var phaseProgress: Double {
        remappedPhase(for: flipProgress)
    }

    private var edgeOnProgress: Double {
        max(0, 1 - abs((phaseProgress * 2) - 1))
    }

    private var flipAngle: Double {
        -180 * phaseProgress
    }

    private var displayedAlbumArt: NSImage {
        guard musicManager.isFlipping else { return musicManager.albumArt }
        guard flipProgress >= artworkRevealProgressThreshold else { return musicManager.flipSourceAlbumArt }
        return targetAlbumArt
    }

    private var targetAlbumArt: NSImage {
        musicManager.pendingAlbumArt ?? musicManager.albumArt
    }

    private var imageFaceRotation: Double {
        flipProgress >= artworkRevealProgressThreshold ? 180 : 0
    }

    private var imageOpacity: Double {
        guard musicManager.isFlipping else { return 1 }

        if flipProgress < artworkRevealProgressThreshold {
            return 1 - smoothStep(phaseProgress, start: 0.46, end: 0.5)
        }

        return smoothStep(flipProgress, start: artworkRevealProgressThreshold, end: 0.8)
    }

    private var blurRadius: CGFloat {
        guard musicManager.isFlipping else { return 0 }

        let edgeBlurProgress = pow(edgeOnProgress, 0.8)
        let sourceLeadIn = flipProgress < artworkRevealProgressThreshold
            ? smoothStep(flipProgress, start: 0.02, end: 0.18) * 0.32
            : 0
        let blurProgress = min(1, edgeBlurProgress + sourceLeadIn)
        return blurProgress * 11.2
    }

    private var darkeningOpacity: Double {
        0.018 + (edgeOnProgress * 0.18)
    }

    private var borderOpacity: Double {
        0.01 + (edgeOnProgress * 0.085)
    }

    private var highlightOpacity: Double {
        0.015 + (edgeOnProgress * 0.12)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glowColor: Color {
        Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.68)
    }

    private var glowOpacity: Double {
        musicManager.isPlaying ? 0.30 : 0.18
    }

    private var glowRadius: CGFloat {
        12
    }

    var body: some View {
        ZStack {
            Image(nsImage: displayedAlbumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .rotation3DEffect(
                    .degrees(imageFaceRotation),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    perspective: 0
                )
                .opacity(imageOpacity)
                .blur(radius: blurRadius)
                .saturation(1 - (edgeOnProgress * 0.08))
                .contrast(1 - (edgeOnProgress * 0.045))
                .brightness(edgeOnProgress * 0.012)

            cardShape
                .fill(.black.opacity(darkeningOpacity))

            cardShape
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(highlightOpacity),
                            .white.opacity(highlightOpacity * 0.28),
                            .clear,
                            .black.opacity(edgeOnProgress * 0.08),
                        ],
                        startPoint: phaseProgress < 0.5 ? .topLeading : .topTrailing,
                        endPoint: phaseProgress < 0.5 ? .bottomTrailing : .bottomLeading
                    )
                )
        }
        .clipShape(cardShape, style: FillStyle(antialiased: true))
        .overlay {
            cardShape
                .strokeBorder(.white.opacity(borderOpacity), lineWidth: 0.7, antialiased: true)
        }
        .compositingGroup()
        .drawingGroup(opaque: false, colorMode: .linear)
        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        .rotation3DEffect(
            .degrees(flipAngle),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.12
        )
        .rotation3DEffect(
            .degrees(hoverTilt.height),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.75
        )
        .rotation3DEffect(
            .degrees(hoverTilt.width),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.75
        )
        .shadow(
            color: glowColor.opacity(glowOpacity),
            radius: glowRadius,
            y: 0
        )
        .shadow(
            color: .black.opacity(0.1 + (edgeOnProgress * 0.08)),
            radius: 10 + (edgeOnProgress * 4),
            y: 2 + (edgeOnProgress * 2)
        )
    }

    private func remappedPhase(for progress: Double) -> Double {
        switch progress {
        case ..<0.24:
            interpolate(0, 0.14, smoothStep(progress, start: 0, end: 0.24))
        case ..<0.52:
            interpolate(0.14, 0.52, smoothStep(progress, start: 0.24, end: 0.52))
        case ..<0.72:
            interpolate(0.52, 0.88, smoothStep(progress, start: 0.52, end: 0.72))
        default:
            interpolate(0.88, 1, smoothStep(progress, start: 0.72, end: 1))
        }
    }

    private func smoothStep(_ value: Double, start: Double, end: Double) -> Double {
        let progress = min(max((value - start) / (end - start), 0), 1)
        return progress * progress * (3 - (2 * progress))
    }

    private func interpolate(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + ((end - start) * progress)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    @State private var isHovering = false
    @State private var hoverTilt: CGSize = .zero

    private let maxTiltDegrees: CGFloat = 5

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
    }

    private var albumArtButton: some View {
        GeometryReader { geo in
            ZStack {
                Button {
                    musicManager.openMusicApp()
                } label: {
                    albumArtImage
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(musicManager.isPlaying ? (isHovering ? 1.018 : 1) : 0.92)

                albumArtDarkOverlay
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    updateHoverTilt(location: location, size: geo.size)
                case .ended:
                    withAnimation(.smooth(duration: 0.22)) {
                        isHovering = false
                        hoverTilt = .zero
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var albumArtDarkOverlay: some View {
        RoundedRectangle(
            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened,
            style: .continuous
        )
        .fill(.black)
        .aspectRatio(1, contentMode: .fit)
        .opacity(musicManager.isPlaying ? 0 : 0.45)
        .blur(radius: 5)
    }

    private var albumArtImage: some View {
        FlippingAlbumArtCard(
            albumArtNamespace: albumArtNamespace,
            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened,
            hoverTilt: hoverTilt,
            isHovering: isHovering
        )
    }

    private func updateHoverTilt(location: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let normalizedX = ((location.x / size.width) - 0.5) * 2
        let normalizedY = ((location.y / size.height) - 0.5) * 2
        let nextTilt = CGSize(
            width: normalizedX * maxTiltDegrees,
            height: -normalizedY * maxTiltDegrees
        )

        withAnimation(.smooth(duration: 0.14)) {
            isHovering = true
            hoverTilt = nextTilt
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    @Default(.enableLyrics) private var enableLyrics
    let albumArtNamespace: Namespace.ID

    private let controlHeight: CGFloat = 64
    private let lyricRowHeight: CGFloat = 11
    private let lyricDisplayDelay: Double = 0.4

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: showsSyncedLyrics && musicManager.playbackRate > 0 ? 0.25 : nil)) { timeline in
                songInfo(width: geo.size.width, currentDate: timeline.date)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: controlHeight)
        .buttonStyle(PlainButtonStyle())
    }

    private var showsSyncedLyrics: Bool {
        enableLyrics && !musicManager.isFetchingLyrics && !musicManager.syncedLyrics.isEmpty
    }

    private var metadataTopInset: CGFloat {
        18
    }

    private var lyricTopInset: CGFloat {
        2
    }

    private func songInfo(width: CGFloat, currentDate: Date? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            metadataView(width: width, currentDate: currentDate)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                MusicSpectrumIndicatorView(
                    albumArtNamespace: albumArtNamespace,
                    isPlaying: musicManager.isPlaying,
                    avgColor: musicManager.avgColor,
                    barWidth: 65,
                    spectrumSize: CGSize(width: 19, height: 14),
                    containerSize: CGSize(width: 29, height: 26),
                    cornerRadius: 8
                )
                .offset(y: -12)
            }
            .padding(.top, metadataTopInset)
        }
        .frame(height: controlHeight, alignment: .top)
    }

    private func metadataView(width: CGFloat, currentDate: Date?) -> some View {
        let metadataWidth = max(0, width - 36)

        return ZStack(alignment: .topLeading) {
            if showsSyncedLyrics, let currentDate {
                syncedLyricLineView(width: metadataWidth, currentDate: currentDate)
                    .transition(lyricLineTransition)
                    .padding(.top, lyricTopInset)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                titleView(width: metadataWidth)
                artistView(width: metadataWidth)
            }
            .padding(.top, metadataTopInset)
        }
        .frame(width: metadataWidth, height: controlHeight, alignment: .topLeading)
        .clipped()
        .animation(.smooth(duration: 0.22), value: showsSyncedLyrics)
    }

    private var metadataTextTransition: AnyTransition {
        .horizontalBlurFade(insertionX: -14, removalX: 14, blur: 7)
    }

    private func titleView(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            MarqueeText(
                $musicManager.songTitle,
                font: .system(size: 13.5, weight: .semibold),
                nsFont: .headline,
                textColor: .white,
                frameWidth: width
            )
            .id(musicManager.songTitle)
            .fontWeight(.medium)
            .contentTransition(.interpolate)
            .transition(metadataTextTransition)
        }
        .clipped()
        .animation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.22), value: musicManager.songTitle)
        .alignmentGuide(.musicTitleRow) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }

    private func artistView(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            MarqueeText(
                $musicManager.artistName,
                font: .system(size: 12.5, weight: .medium),
                nsFont: .headline,
                textColor: matchAlbumArtColor
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                    : .gray,
                frameWidth: width
            )
            .id(musicManager.artistName)
            .fontWeight(.regular)
            .contentTransition(.interpolate)
            .transition(metadataTextTransition)
        }
        .clipped()
        .animation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.22), value: musicManager.artistName)
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
                    .init(color: .clear, location: 1),
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
        let baseElapsed: Double

        if musicManager.isPlaying {
            let delta = currentDate.timeIntervalSince(musicManager.timestampDate)
            baseElapsed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
        } else {
            baseElapsed = musicManager.elapsedTime
        }

        return min(max(baseElapsed - lyricDisplayDelay, 0), musicManager.songDuration)
    }

    private func lyricLineFont(for text: String) -> Font {
        if text.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF }) {
            return .custom("Vazirmatn-Regular", size: 11.50)
        }

        return .system(size: 11.50, weight: .medium)
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
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.72)
            : .white
    }

    private var inactiveControlColor: Color {
        if matchAlbumArtColor,
           let rgbColor = musicManager.avgColor.usingColorSpace(.sRGB)
        {
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            return Color(
                hue: Double(hue),
                saturation: Double(max(0.08, saturation * 0.16)),
                brightness: Double(max(0.34, brightness * 0.42)),
                opacity: 0.9
            )
        }

        return Color.white.opacity(0.3)
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? activeControlColor : inactiveControlColor,
                backgroundColor: .clear,
                scale: .medium,
                tapEffect: .rotateCounterClockwise
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .lyrics:
            HoverButton(
                icon: "quote.bubble",
                iconColor: enableLyrics ? activeControlColor : inactiveControlColor,
                backgroundColor: .clear,
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
    private var cornerRadius: CGFloat {
        size * 0.28
    }

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

struct LockScreenMediaView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.lockScreenPlayerStyle) private var lockScreenPlayerStyle
    let albumArtNamespace: Namespace.ID

    private var backgroundFill: AnyShapeStyle {
        switch lockScreenPlayerStyle {
        case .default:
            AnyShapeStyle(.ultraThinMaterial)
        case .frosted:
            AnyShapeStyle(Color.white.opacity(0.12))
        }
    }

    private var strokeOpacity: Double {
        switch lockScreenPlayerStyle {
        case .default:
            0.075
        case .frosted:
            0.065
        }
    }

    private var shadowOpacity: Double {
        switch lockScreenPlayerStyle {
        case .default:
            0.18
        case .frosted:
            0.16
        }
    }

    private var highlightOpacity: Double {
        switch lockScreenPlayerStyle {
        case .default:
            0.06
        case .frosted:
            0.04
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    FlippingAlbumArtCard(
                        albumArtNamespace: albumArtNamespace,
                        cornerRadius: 14,
                        hoverTilt: .zero,
                        isHovering: false
                    )
                    .frame(width: 64, height: 64)
                    .scaleEffect(musicManager.isPlaying ? 1 : 0.94)

                    HStack(alignment: .center, spacing: 4) {
                        LockScreenMetadataView(width: 194)

                        MusicSpectrumIndicatorView(
                            albumArtNamespace: albumArtNamespace,
                            isPlaying: musicManager.isPlaying,
                            avgColor: musicManager.avgColor,
                            barWidth: 52,
                            spectrumSize: CGSize(width: 17, height: 12),
                            containerSize: CGSize(width: 24, height: 22),
                            cornerRadius: 7
                        )
                        .offset(y: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LockScreenProgressView()

                LockScreenControlsRow()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 328, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(highlightOpacity),
                                    .clear,
                                    .white.opacity(highlightOpacity * 0.35),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(strokeOpacity), lineWidth: 0.8)
                }
        )
        .compositingGroup()
        .shadow(color: .black.opacity(shadowOpacity), radius: 22, y: 10)
    }
}

struct LockScreenMediaOverlayView: View {
    @Namespace private var albumArtNamespace
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.clear

            LockScreenMediaView(albumArtNamespace: albumArtNamespace)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onAppear {
            isVisible = false

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.16)) {
                    isVisible = true
                }
            }
        }
        .onDisappear {
            isVisible = false
        }
    }
}

private struct LockScreenMetadataView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    let width: CGFloat

    private var metadataTextTransition: AnyTransition {
        .horizontalBlurFade(insertionX: -14, removalX: 14, blur: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleView
            artistView
        }
        .frame(width: width, height: 42, alignment: .center)
        .clipped()
    }

    private var titleView: some View {
        ZStack(alignment: .leading) {
            MarqueeText(
                $musicManager.songTitle,
                font: .system(size: 13.5, weight: .semibold),
                nsFont: .headline,
                textColor: .white,
                frameWidth: width
            )
            .id(musicManager.songTitle)
            .contentTransition(.interpolate)
            .transition(metadataTextTransition)
        }
        .clipped()
        .animation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.22), value: musicManager.songTitle)
    }

    private var artistView: some View {
        ZStack(alignment: .leading) {
            MarqueeText(
                $musicManager.artistName,
                font: .system(size: 11.5, weight: .medium),
                nsFont: .subheadline,
                textColor: matchAlbumArtColor
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                    : .white.opacity(0.58),
                frameWidth: width
            )
            .id(musicManager.artistName)
            .contentTransition(.interpolate)
            .transition(metadataTextTransition)
        }
        .clipped()
        .animation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.22), value: musicManager.artistName)
    }
}

private struct LockScreenProgressView: View {
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

private struct LockScreenControlsRow: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor

    private var activeControlColor: Color {
        matchAlbumArtColor
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.72)
            : .white
    }

    private var inactiveControlColor: Color {
        if matchAlbumArtColor,
           let rgbColor = musicManager.avgColor.usingColorSpace(.sRGB)
        {
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            return Color(
                hue: Double(hue),
                saturation: Double(max(0.08, saturation * 0.16)),
                brightness: Double(max(0.34, brightness * 0.42)),
                opacity: 0.9
            )
        }

        return Color.white.opacity(0.3)
    }

    var body: some View {
        HStack(spacing: 10) {
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? activeControlColor : inactiveControlColor,
                backgroundColor: .clear,
                scale: .medium,
                tapEffect: .rotateCounterClockwise
            ) {
                MusicManager.shared.toggleShuffle()
            }

            HoverButton(icon: "backward.fill", scale: .medium, tapEffect: .nudgeLeft) {
                MusicManager.shared.previousTrack()
            }

            OptimisticPlayPauseButton()

            HoverButton(icon: "forward.fill", scale: .medium, tapEffect: .nudgeRight) {
                MusicManager.shared.nextTrack()
            }

            HoverButton(icon: "laptopcomputer", backgroundColor: .clear, scale: .medium) {}
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

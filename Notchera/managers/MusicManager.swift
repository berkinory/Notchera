import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = {
    let image = NSImage(size: NSSize(width: 256, height: 256))
    image.isTemplate = false
    return image
}()

private struct PendingSeek {
    let position: TimeInterval
    let requestedAt: Date
}

private struct PendingTrackChange {
    let requestedAt: Date
    let previousTrackIdentifier: String
}

class MusicManager: ObservableObject {
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var artworkFallbackTask: Task<Void, Never>?

    private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    private var activeController: (any MediaControllerProtocol)?

    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: NotcheraAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String?
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data?
    private var pendingSeek: PendingSeek?
    private var pendingTrackChange: PendingTrackChange?

    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String?

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    init() {
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }

            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }

    func destroy() {
        debounceIdleTask?.cancel()
        artworkFallbackTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        activeController = nil
    }

    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            if !isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self,
                          activeController === controller else { return }
                    updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        let controllerType = (isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        flipWorkItem?.cancel()

        activeController = controller

        canFavoriteTrack = controller.supportsFavorite

        forceUpdate()
    }

    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        let incomingTrackIdentifier = trackIdentifier(
            bundleIdentifier: state.bundleIdentifier,
            title: state.title,
            artist: state.artist,
            album: state.album
        )

        if state.isPlaying != isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }
        }

        let titleChanged = state.title != lastArtworkTitle
        let artistChanged = state.artist != lastArtworkArtist
        let albumChanged = state.album != lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != lastArtworkBundleIdentifier

        let artworkChanged = state.artwork != nil && state.artwork != artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        if hasContentChange {
            if artworkChanged, let artwork = state.artwork {
                artworkFallbackTask?.cancel()
                triggerFlipAnimation()
                updateArtwork(artwork)
                artworkData = artwork
            } else if state.artwork == nil {
                usingAppIconForArtwork = false
                artworkData = nil
                scheduleArtworkFallback(for: incomingTrackIdentifier)
            }

            lastArtworkTitle = state.title
            lastArtworkArtist = state.artist
            lastArtworkAlbum = state.album
            lastArtworkBundleIdentifier = state.bundleIdentifier

            fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let playbackTimeState = resolvedPlaybackTimeState(for: state)
        let shouldApplyTimeState = playbackTimeState.shouldApply
        let timeChanged = state.currentTime != elapsedTime
        let durationChanged = state.duration != songDuration
        let playbackRateChanged = state.playbackRate != playbackRate
        let shuffleChanged = state.isShuffled != isShuffled
        let repeatModeChanged = state.repeatMode != repeatMode
        let volumeChanged = state.volume != volume

        if state.title != songTitle {
            songTitle = state.title
        }

        if state.artist != artistName {
            artistName = state.artist
        }

        if state.album != album {
            album = state.album
        }

        if shouldApplyTimeState, timeChanged {
            elapsedTime = state.currentTime
        }

        if durationChanged {
            songDuration = state.duration
        }

        if playbackRateChanged {
            playbackRate = state.playbackRate
        }

        if shuffleChanged {
            isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != bundleIdentifier {
            bundleIdentifier = state.bundleIdentifier
            volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        if repeatModeChanged {
            repeatMode = state.repeatMode
        }
        if state.isFavorite != isFavoriteTrack {
            isFavoriteTrack = state.isFavorite
        }

        if volumeChanged {
            volume = state.volume
        }

        if shouldApplyTimeState {
            timestampDate = state.lastUpdated
        }

        pendingSeek = playbackTimeState.pendingSeek
        pendingTrackChange = playbackTimeState.pendingTrackChange
    }

    private func resolvedPlaybackTimeState(for state: PlaybackState) -> (
        shouldApply: Bool,
        pendingSeek: PendingSeek?,
        pendingTrackChange: PendingTrackChange?
    ) {
        let now = Date()
        let incomingTrackIdentifier = trackIdentifier(
            bundleIdentifier: state.bundleIdentifier,
            title: state.title,
            artist: state.artist,
            album: state.album
        )

        if let pendingTrackChange {
            let age = now.timeIntervalSince(pendingTrackChange.requestedAt)
            let trackChanged = incomingTrackIdentifier != pendingTrackChange.previousTrackIdentifier
            let isStaleState = state.lastUpdated < pendingTrackChange.requestedAt
            let restartedCurrentTrack = !isStaleState && !trackChanged && state.currentTime <= 1.5

            if trackChanged || restartedCurrentTrack || age > 1.25 {
                return (true, pendingSeek, nil)
            }

            if isStaleState || state.currentTime > 2 {
                return (false, pendingSeek, pendingTrackChange)
            }

            return (true, pendingSeek, nil)
        }

        guard let pendingSeek else { return (true, nil, nil) }

        let age = now.timeIntervalSince(pendingSeek.requestedAt)
        let matchesPendingSeek = abs(state.currentTime - pendingSeek.position) <= 0.75
        let isStaleState = state.lastUpdated < pendingSeek.requestedAt
        let trackChanged = incomingTrackIdentifier != currentTrackIdentifier

        if matchesPendingSeek || trackChanged || age > 1.5 {
            return (true, nil, nil)
        }

        if isStaleState || abs(state.currentTime - pendingSeek.position) > 0.75 {
            return (false, pendingSeek, nil)
        }

        return (true, nil, nil)
    }

    private var currentTrackIdentifier: String {
        trackIdentifier(
            bundleIdentifier: bundleIdentifier ?? "",
            title: songTitle,
            artist: artistName,
            album: album
        )
    }

    private func trackIdentifier(bundleIdentifier: String, title: String, artist: String, album: String) -> String {
        [bundleIdentifier, title, artist, album].joined(separator: "\u{1F}")
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            isFavoriteTrack = loved
            forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    func setLyricsEnabled(_ enabled: Bool) {
        Defaults[.enableLyrics] = enabled
        fetchLyricsIfAvailable(bundleIdentifier: bundleIdentifier, title: songTitle, artist: artistName)
    }

    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            DispatchQueue.main.async {
                self.isFetchingLyrics = false
                self.currentLyrics = ""
            }
            return
        }

        if let bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: title, artist: artist)
                    return
                }

                self.isFetchingLyrics = true
                self.currentLyrics = ""
                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script), let lyricsString = result.stringValue, !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {}
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        } else {
            Task { @MainActor in
                self.isFetchingLyrics = true
                self.currentLyrics = ""
                await self.fetchLyricsFromWeb(title: title, artist: artist)
            }
        }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String) async {
        let cleanTitle = normalizedQuery(title)
        let cleanArtist = normalizedQuery(artist)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            currentLyrics = ""
            isFetchingLyrics = false
            return
        }

        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else {
            currentLyrics = ""
            isFetchingLyrics = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                currentLyrics = ""
                isFetchingLyrics = false
                return
            }
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first
            {
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolved = plain.isEmpty ? synced : plain
                currentLyrics = resolved
                isFetchingLyrics = false
                if !synced.isEmpty {
                    syncedLyrics = parseLRC(synced)
                } else {
                    syncedLyrics = []
                }
            } else {
                currentLyrics = ""
                isFetchingLyrics = false
                syncedLyrics = []
            }
        } catch {
            currentLyrics = ""
            isFetchingLyrics = false
            syncedLyrics = []
        }
    }

    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        for lineSub in lrc.split(separator: "\n") {
            let line = String(lineSub)
            let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                let centiStr = csRange.location != NSNotFound ? nsLine.substring(with: csRange) : "0"
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let time = minutes * 60 + seconds + centis / 100.0
                let textStart = match.range.location + match.range.length
                let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    result.append((time, text))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func lyricIndex(at elapsed: Double) -> Int? {
        guard !syncedLyrics.isEmpty else { return nil }
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }

    func lyricLine(at elapsed: Double) -> String {
        guard let idx = lyricIndex(at: elapsed) else { return currentLyrics }
        return syncedLyrics[idx].text
    }

    private func triggerFlipAnimation() {
        flipWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleArtworkFallback(for trackIdentifier: String) {
        artworkFallbackTask?.cancel()
        artworkFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.currentTrackIdentifier == trackIdentifier else { return }
                guard self.artworkData == nil else { return }
                self.updateAlbumArt(newAlbumArt: defaultImage)
            }
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            self.calculateAverageColor()
        }
    }

    func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }

    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        let requestedAt = Date()
        pendingSeek = nil
        pendingTrackChange = PendingTrackChange(
            requestedAt: requestedAt,
            previousTrackIdentifier: currentTrackIdentifier
        )
        elapsedTime = 0
        timestampDate = requestedAt

        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        let requestedAt = Date()
        pendingSeek = nil
        pendingTrackChange = PendingTrackChange(
            requestedAt: requestedAt,
            previousTrackIdentifier: currentTrackIdentifier
        )
        elapsedTime = 0
        timestampDate = requestedAt

        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        let clampedPosition = min(max(0, position), songDuration)

        Task { [weak self] in
            guard let self else { return }

            let requestedAt = Date()
            await MainActor.run {
                self.pendingTrackChange = nil
                self.pendingSeek = PendingSeek(position: clampedPosition, requestedAt: requestedAt)
                self.elapsedTime = clampedPosition
                self.timestampDate = requestedAt
            }

            await self.activeController?.seek(to: clampedPosition)
        }
    }

    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }

    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }

    func syncVolumeFromActiveApp() async {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }

        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            return
        }

        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript)
        {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0

            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}

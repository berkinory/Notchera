import Defaults
import SwiftUI

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

/// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

/// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    var id: String {
        rawValue
    }
}

extension Defaults.Keys {
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)

    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.2)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let trackpadTabSwitch = Key<Bool>("trackpadTabSwitch", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    static let hideNotchInFullscreen = Key<Bool>("hideNotchInFullscreen", default: true)

    static let showEmojis = Key<Bool>("showEmojis", default: false)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)

    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let matchAlbumArtColor = Key<Bool>("sliderUseAlbumArtColor", default: false)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )

    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)

    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let showVolumeIndicator = Key<Bool>("showVolumeIndicator", default: true)
    static let showBrightnessIndicator = Key<Bool>("showBrightnessIndicator", default: true)
    static let showBacklightIndicator = Key<Bool>("showBacklightIndicator", default: true)
    static let showCapsLockIndicator = Key<Bool>("showCapsLockIndicator", default: true)
    static let showInputSourceIndicator = Key<Bool>("showInputSourceIndicator", default: true)
    static let showFocusIndicator = Key<Bool>("showFocusIndicator", default: true)
    static let showBluetoothAudioIndicator = Key<Bool>("showBluetoothAudioIndicator", default: true)
    static let animateBluetoothAudioIndicator = Key<Bool>("animateBluetoothAudioIndicator", default: true)
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let enableScreenRecordingDetection = Key<Bool>("enableScreenRecordingDetection", default: true)

    static let notchShelf = Key<Bool>("notchShelf", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: true)

    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)

    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            .appleMusic
        } else {
            .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}

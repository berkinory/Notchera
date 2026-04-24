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

extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic = "Automatic"
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    var id: String {
        rawValue
    }
}

enum ClipboardSelectionAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case copy = "Copy"
    case paste = "Paste"

    var id: String {
        rawValue
    }
}

extension Defaults.Keys {
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: false)

    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.2)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let trackpadTabSwitch = Key<Bool>("trackpadTabSwitch", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: true)
    static let showHUDOnLockScreen = Key<Bool>("showHUDOnLockScreen", default: true)
    static let showLockScreenMediaPlayer = Key<Bool>("showLockScreenMediaPlayer", default: true)
    static let lockScreenPlayerStyle = Key<LockScreenPlayerStyle>("lockScreenPlayerStyle", default: .frosted)
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

    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let showVolumeIndicator = Key<Bool>("showVolumeIndicator", default: true)
    static let showBrightnessIndicator = Key<Bool>("showBrightnessIndicator", default: true)
    static let showBacklightIndicator = Key<Bool>("showBacklightIndicator", default: true)
    static let showSystemValueInHUD = Key<Bool>("showSystemValueInHUD", default: true)
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
    static let enableClipboardHistory = Key<Bool>("enableClipboardHistory", default: true)
    static let hideClipboardFromTabs = Key<Bool>("hideClipboardFromTabs", default: false)
    static let clipboardSelectionAction = Key<ClipboardSelectionAction>("clipboardSelectionAction", default: .paste)
    static let clipboardHistoryRetention = Key<ClipboardHistoryRetention>("clipboardHistoryRetention", default: .oneWeek)
    static let clipboardHistoryMaxStoredItems = Key<Int>("clipboardHistoryMaxStoredItems", default: 50)
    static let preventSleepEnabled = Key<Bool>("preventSleepEnabled", default: false)
    static let preventSleepExpiresAt = Key<Double?>("preventSleepExpiresAt", default: nil)
    static let enableCommandLauncher = Key<Bool>("enableCommandLauncher", default: true)
    static let hideLauncherFromTabs = Key<Bool>("hideLauncherFromTabs", default: false)
    static let enableCommandLauncherCalculator = Key<Bool>("enableCommandLauncherCalculator", default: true)
    static let enableCommandLauncherCurrencyConversion = Key<Bool>("enableCommandLauncherCurrencyConversion", default: true)

    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)

    static var defaultMediaController: MediaControllerType {
        .automatic
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
    static let enableAIUsage = Key<Bool>("enableAIUsage", default: false)
    static let aiUsageShowRemaining = Key<Bool>("aiUsageShowRemaining", default: false)
}

import Defaults
import Foundation

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews: String {
    case home
    case calendar
    case clipboard
    case shelf
    case aiUsage
    case commandPalette
}

public enum CommandPaletteModule {
    case appLauncher
    case clipboard
}

enum SettingsEnum {
    case general
    case about
    case charge
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
}

enum LockScreenPlayerStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case `default` = "Default"
    case frosted = "Frosted"

    var id: String {
        rawValue
    }
}

enum ClipboardHistoryRetention: String, CaseIterable, Identifiable, Defaults.Serializable {
    case oneHour = "1 hour"
    case twelveHours = "12 hours"
    case oneDay = "1 day"
    case threeDays = "3 days"
    case oneWeek = "7 days"

    var id: String {
        rawValue
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneHour:
            3600
        case .twelveHours:
            43_200
        case .oneDay:
            86_400
        case .threeDays:
            259_200
        case .oneWeek:
            604_800
        }
    }
}

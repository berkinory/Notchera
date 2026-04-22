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

enum ClipboardHistoryRetention: String, CaseIterable, Identifiable, Defaults.Serializable {
    case oneHour = "1 hour"
    case oneDay = "1 day"
    case oneWeek = "1 week"

    var id: String {
        rawValue
    }

    var timeInterval: TimeInterval {
        switch self {
        case .oneHour:
            3600
        case .oneDay:
            86400
        case .oneWeek:
            604_800
        }
    }
}

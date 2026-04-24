import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case lyrics
    case previous
    case playPause
    case next
    case goBackward
    case goForward
    case none

    var id: String {
        rawValue
    }

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .none,
        .previous,
        .playPause,
        .next,
        .none,
        .none,
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 7

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .lyrics,
        .previous,
        .playPause,
        .next,
        .goBackward,
        .goForward,
    ]

    var label: String {
        switch self {
        case .shuffle:
            "Shuffle"
        case .lyrics:
            "Lyrics"
        case .previous:
            "Previous"
        case .playPause:
            "Play/Pause"
        case .next:
            "Next"
        case .goBackward:
            "Backward 15s"
        case .goForward:
            "Forward 15s"
        case .none:
            "Empty slot"
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            "shuffle"
        case .lyrics:
            "quote.bubble"
        case .previous:
            "backward.fill"
        case .playPause:
            "playpause"
        case .next:
            "forward.fill"
        case .goBackward:
            "gobackward.15"
        case .goForward:
            "goforward.15"
        case .none:
            ""
        }
    }

    var shortLabel: String {
        switch self {
        case .shuffle:
            "Shuffle"
        case .lyrics:
            "Lyrics"
        case .previous:
            "Previous"
        case .playPause:
            "Play/Pause"
        case .next:
            "Next"
        case .goBackward:
            "Back 15s"
        case .goForward:
            "Forward 15s"
        case .none:
            "Empty"
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}

import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case none

    var id: String {
        rawValue
    }

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .previous,
        .playPause,
        .next,
        .none,
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 5

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .repeatMode,
        .favorite,
        .volume,
        .goBackward,
        .goForward,
    ]

    var label: String {
        switch self {
        case .shuffle:
            "Shuffle"
        case .previous:
            "Previous"
        case .playPause:
            "Play/Pause"
        case .next:
            "Next"
        case .repeatMode:
            "Repeat"
        case .volume:
            "Volume"
        case .favorite:
            "Favorite"
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
        case .previous:
            "backward.fill"
        case .playPause:
            "playpause"
        case .next:
            "forward.fill"
        case .repeatMode:
            "repeat"
        case .volume:
            "speaker.wave.2.fill"
        case .favorite:
            "heart"
        case .goBackward:
            "gobackward.15"
        case .goForward:
            "goforward.15"
        case .none:
            ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}

import Foundation

enum ReleaseChannel: String {
    case direct
    case brew

    static var current: ReleaseChannel {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "NotcheraReleaseChannel") as? String,
              let channel = ReleaseChannel(rawValue: rawValue)
        else {
            return .direct
        }
        return channel
    }

    static var usesSparkleUpdates: Bool {
        current == .direct
    }
}

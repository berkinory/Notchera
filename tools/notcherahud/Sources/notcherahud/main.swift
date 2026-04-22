import Foundation

enum Side: String {
    case left
    case right
}

struct HUDColor: Codable {
    static let tokenValues = ["primary", "secondary", "green", "yellow", "red", "blue"]

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum HUDItemType: String, Codable {
    case icon
    case text
    case value
    case slider
}

struct HUDItem: Codable {
    let type: HUDItemType
    var text: String?
    var symbol: String?
    var value: Double?
    var color: HUDColor?
}

struct HUDRequest: Codable {
    let id: String?
    let duration: Double
    let left: [HUDItem]
    let right: [HUDItem]
}

enum CLIError: LocalizedError {
    case unknownFlag(String)
    case missingValue(String)
    case invalidNumber(flag: String, value: String)
    case invalidColor(side: Side, value: String)
    case noItemToColor(Side)
    case emptyRequest
    case tooManyItems(side: Side, max: Int)

    var errorDescription: String? {
        switch self {
        case let .unknownFlag(flag):
            "unknown flag: \(flag)"
        case let .missingValue(flag):
            "missing value for \(flag)"
        case let .invalidNumber(flag, value):
            "invalid numeric value for \(flag): \(value)"
        case let .invalidColor(side, value):
            "invalid \(side.rawValue) color: \(value). expected a token \(HUDColor.tokenValues.joined(separator: ", ")) or a hex like #7C3AED or #7C3AEDFF"
        case let .noItemToColor(side):
            "\(side.rawValue) color was provided before any \(side.rawValue) item"
        case .emptyRequest:
            "at least one left or right item is required"
        case let .tooManyItems(side, max):
            "too many \(side.rawValue) items. max is \(max)"
        }
    }
}

@main
struct NotcheraHUDCLI {
    static func main() {
        do {
            let request = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try post(request)
        } catch {
            fputs("error: \(error.localizedDescription)\n\n", stderr)
            fputs(helpText, stderr)
            exit(1)
        }
    }

    private static func parse(arguments: [String]) throws -> HUDRequest {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(helpText)
            exit(0)
        }

        var durationMilliseconds = 1500
        var left: [HUDItem] = []
        var right: [HUDItem] = []
        var index = 0

        while index < arguments.count {
            let flag = arguments[index]
            index += 1

            switch flag {
            case "--duration":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                guard let parsed = Int(raw) else {
                    throw CLIError.invalidNumber(flag: flag, value: raw)
                }
                durationMilliseconds = max(500, min(parsed, 2500))
            case "--left-icon":
                let symbol = try readValue(after: flag, from: arguments, index: &index)
                left.append(HUDItem(type: .icon, text: nil, symbol: symbol, value: nil, color: nil))
            case "--left-text":
                let text = try readValue(after: flag, from: arguments, index: &index)
                left.append(HUDItem(type: .text, text: text, symbol: nil, value: nil, color: nil))
            case "--left-value":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                guard let parsed = Double(raw) else {
                    throw CLIError.invalidNumber(flag: flag, value: raw)
                }
                left.append(HUDItem(type: .value, text: nil, symbol: nil, value: parsed, color: nil))
            case "--left-slider":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                guard let parsed = Double(raw) else {
                    throw CLIError.invalidNumber(flag: flag, value: raw)
                }
                left.append(HUDItem(type: .slider, text: nil, symbol: nil, value: max(0, min(parsed, 1)), color: nil))
            case "--right-icon":
                let symbol = try readValue(after: flag, from: arguments, index: &index)
                right.append(HUDItem(type: .icon, text: nil, symbol: symbol, value: nil, color: nil))
            case "--right-text":
                let text = try readValue(after: flag, from: arguments, index: &index)
                right.append(HUDItem(type: .text, text: text, symbol: nil, value: nil, color: nil))
            case "--right-value":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                guard let parsed = Double(raw) else {
                    throw CLIError.invalidNumber(flag: flag, value: raw)
                }
                right.append(HUDItem(type: .value, text: nil, symbol: nil, value: parsed, color: nil))
            case "--right-slider":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                guard let parsed = Double(raw) else {
                    throw CLIError.invalidNumber(flag: flag, value: raw)
                }
                right.append(HUDItem(type: .slider, text: nil, symbol: nil, value: max(0, min(parsed, 1)), color: nil))
            case "--left-color":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                let color = try parseColor(raw, side: .left)
                guard !left.isEmpty else {
                    throw CLIError.noItemToColor(.left)
                }
                left[left.index(before: left.endIndex)].color = color
            case "--right-color":
                let raw = try readValue(after: flag, from: arguments, index: &index)
                let color = try parseColor(raw, side: .right)
                guard !right.isEmpty else {
                    throw CLIError.noItemToColor(.right)
                }
                right[right.index(before: right.endIndex)].color = color
            default:
                throw CLIError.unknownFlag(flag)
            }
        }

        guard !left.isEmpty || !right.isEmpty else {
            throw CLIError.emptyRequest
        }

        if left.count > 2 {
            throw CLIError.tooManyItems(side: .left, max: 2)
        }

        if right.count > 3 {
            throw CLIError.tooManyItems(side: .right, max: 3)
        }

        return HUDRequest(id: nil, duration: Double(durationMilliseconds) / 1000, left: left, right: right)
    }

    private static func readValue(after flag: String, from arguments: [String], index: inout Int) throws -> String {
        guard index < arguments.count else {
            throw CLIError.missingValue(flag)
        }

        let value = arguments[index]
        index += 1
        return value
    }

    private static func parseColor(_ raw: String, side: Side) throws -> HUDColor {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if HUDColor.tokenValues.contains(lowercased) {
            return HUDColor(rawValue: lowercased)
        }

        if isHexColor(trimmed) {
            return HUDColor(rawValue: trimmed)
        }

        throw CLIError.invalidColor(side: side, value: raw)
    }

    private static func isHexColor(_ raw: String) -> Bool {
        let hex = raw.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6 || hex.count == 8 else {
            return false
        }

        return UInt64(hex, radix: 16) != nil
    }

    private static func post(_ request: HUDRequest) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.notchera.app.externalHUDRequest"),
            object: payload,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private static let helpText = """
usage:
  notcherahud [flags]

flags:
  --duration <milliseconds>

  --left-icon <sf-symbol>
  --left-text <text>
  --left-value <number>
  --left-slider <0...1>
  --left-color <primary|secondary|green|yellow|red|blue|#RRGGBB|#RRGGBBAA>

  --right-icon <sf-symbol>
  --right-text <text>
  --right-value <number>
  --right-slider <0...1>
  --right-color <primary|secondary|green|yellow|red|blue|#RRGGBB|#RRGGBBAA>

notes:
  - left max 2 item
  - right max 3 item
  - color applies to the most recently added item on that side
  - each item can have its own color
  - slider is clamped to 0...1
  - duration is clamped to 500...2500 ms
  - quote hex colors in shell, example "#7C3AED"

examples:
  notcherahud \
    --duration 1800 \
    --left-icon bolt.fill \
    --left-color yellow \
    --left-text "build" \
    --left-color "#F8FAFC" \
    --right-slider 0.72 \
    --right-color "#3B82F6" \
    --right-value 72 \
    --right-color secondary

  notcherahud \
    --left-icon checkmark.circle.fill \
    --left-color green \
    --left-text "deployed" \
    --left-color "#E2E8F0" \
    --right-text "prod" \
    --right-color "#94A3B8"
"""
}

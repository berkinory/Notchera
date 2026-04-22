import AppKit
import Carbon
import Combine
import CoreAudio
import Defaults
import IOBluetooth
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case capsLock
    case inputSource
    case focus
    case bluetoothAudio
    case recording
    case battery
    case hudEnabled
    case custom
}

struct ExternalHUDRequest: Codable, Equatable {
    var id: String?
    var duration: TimeInterval
    var left: [ExternalHUDItem]
    var right: [ExternalHUDItem]

    func normalized() -> ExternalHUDRequest? {
        let left = Array(left.compactMap(\.normalized).prefix(2))
        let right = Array(right.compactMap(\.normalized).prefix(3))

        guard !left.isEmpty || !right.isEmpty else {
            return nil
        }

        return ExternalHUDRequest(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: max(0.5, min(duration, 2.5)),
            left: left,
            right: right
        )
    }

    var animationKey: String {
        let leftKey = left.map(\.animationKey).joined(separator: ",")
        let rightKey = right.map(\.animationKey).joined(separator: ",")
        return "\(leftKey)|\(rightKey)"
    }
}

struct ExternalHUDItem: Codable, Equatable {
    enum ItemType: String, Codable {
        case icon
        case text
        case value
        case slider
        case loading
        case spinner
    }

    var type: ItemType
    var text: String?
    var symbol: String?
    var value: Double?
    var color: ExternalHUDColor?

    var normalized: ExternalHUDItem? {
        let normalizedColor = color?.normalized

        switch type {
        case .icon:
            guard let symbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty else {
                return nil
            }

            return ExternalHUDItem(type: type, text: nil, symbol: symbol, value: nil, color: normalizedColor)
        case .text:
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }

            return ExternalHUDItem(type: type, text: text, symbol: nil, value: nil, color: normalizedColor)
        case .value:
            guard let value else {
                return nil
            }

            return ExternalHUDItem(type: type, text: nil, symbol: nil, value: value, color: normalizedColor)
        case .slider:
            guard let value else {
                return nil
            }

            return ExternalHUDItem(type: type, text: nil, symbol: nil, value: max(0, min(value, 1)), color: normalizedColor)
        case .loading:
            return ExternalHUDItem(type: type, text: nil, symbol: nil, value: nil, color: normalizedColor)
        case .spinner:
            return ExternalHUDItem(type: type, text: nil, symbol: nil, value: nil, color: normalizedColor)
        }
    }

    var animationKey: String {
        switch type {
        case .icon:
            "icon:\(symbol ?? ""):\(color?.rawValue ?? "")"
        case .text:
            "text:\(text ?? ""):\(color?.rawValue ?? "")"
        case .value:
            "value:\(color?.rawValue ?? "")"
        case .slider:
            "slider:\(color?.rawValue ?? "")"
        case .loading:
            "loading:\(color?.rawValue ?? "")"
        case .spinner:
            "spinner:\(color?.rawValue ?? "")"
        }
    }
}

struct ExternalHUDColor: Codable, Equatable {
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

    var normalized: ExternalHUDColor? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return ExternalHUDColor(rawValue: trimmed)
    }

    var swiftUIColor: Color {
        switch rawValue.lowercased() {
        case "primary":
            .white
        case "secondary":
            .gray
        case "green":
            .green
        case "yellow":
            .yellow
        case "red":
            .red
        case "blue":
            .blue
        default:
            Self.hexColor(from: rawValue) ?? .white
        }
    }

    private static func hexColor(from rawValue: String) -> Color? {
        let hex = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16)
        else {
            return nil
        }

        if hex.count == 6 {
            let red = Double((value & 0xFF0000) >> 16) / 255
            let green = Double((value & 0x00FF00) >> 8) / 255
            let blue = Double(value & 0x0000FF) / 255
            return Color(red: red, green: green, blue: blue)
        }

        let red = Double((value & 0xFF00_0000) >> 24) / 255
        let green = Double((value & 0x00FF_0000) >> 16) / 255
        let blue = Double((value & 0x0000_FF00) >> 8) / 255
        let alpha = Double(value & 0x0000_00FF) / 255
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct HUDState: Equatable {
    var show: Bool = false
    var type: SneakContentType = .volume
    var value: CGFloat = 0
    var icon: String = ""
    var label: String = ""
    var duration: TimeInterval = 1.5
    var custom: ExternalHUDRequest?
}

struct SharedHUDState: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
}

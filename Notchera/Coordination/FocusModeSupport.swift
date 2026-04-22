import AppKit
import Defaults

extension Notification.Name {
    static let externalHUDRequest = Notification.Name("com.notchera.app.externalHUDRequest")
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
    static let bluetoothDeviceConnected = Notification.Name("IOBluetoothDeviceConnectedNotification")
    static let bluetoothDeviceDisconnected = Notification.Name("IOBluetoothDeviceDisconnectedNotification")
}

private struct FocusModePresentation {
    let title: String
    let symbol: String
}

private enum FocusModeKind {
    case doNotDisturb
    case work
    case personal
    case sleep
    case driving
    case fitness
    case gaming
    case mindfulness
    case reading
    case custom
    case unknown

    init(identifier: String?, name: String?) {
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalizedName {
        case "work":
            self = .work
            return
        case "personal", "personal-time":
            self = .personal
            return
        case "sleep", "sleep-mode":
            self = .sleep
            return
        case "driving":
            self = .driving
            return
        case "fitness":
            self = .fitness
            return
        case "gaming":
            self = .gaming
            return
        case "mindfulness":
            self = .mindfulness
            return
        case "reading":
            self = .reading
            return
        case "dnd", "default", "do not disturb", "do-not-disturb", "donotdisturb":
            self = .doNotDisturb
            return
        default:
            break
        }

        let normalizedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalizedIdentifier {
        case _ where normalizedIdentifier == "com.apple.donotdisturb.mode":
            self = .doNotDisturb
        case _ where normalizedIdentifier == "com.apple.sleep.sleep-mode":
            self = .sleep
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.work"):
            self = .work
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.personal"):
            self = .personal
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.sleep"):
            self = .sleep
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.driving"):
            self = .driving
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.fitness"):
            self = .fitness
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.gaming"):
            self = .gaming
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.mindfulness"):
            self = .mindfulness
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus.reading"):
            self = .reading
        case _ where normalizedIdentifier.hasPrefix("com.apple.donotdisturb.mode."):
            self = .custom
        case _ where normalizedIdentifier.hasPrefix("com.apple.focus"):
            self = .custom
        case "":
            self = .unknown
        default:
            self = .unknown
        }
    }

    var defaultTitle: String {
        switch self {
        case .doNotDisturb:
            "Do Not Disturb"
        case .work:
            "Work"
        case .personal:
            "Personal"
        case .sleep:
            "Sleep"
        case .driving:
            "Driving"
        case .fitness:
            "Fitness"
        case .gaming:
            "Gaming"
        case .mindfulness:
            "Mindfulness"
        case .reading:
            "Reading"
        case .custom:
            "Focus"
        case .unknown:
            "Focus"
        }
    }

    var symbolName: String {
        switch self {
        case .doNotDisturb:
            "moon.fill"
        case .work:
            "briefcase.fill"
        case .personal:
            "person.fill"
        case .sleep:
            "bed.double.fill"
        case .driving:
            "car.fill"
        case .fitness:
            "figure.run"
        case .gaming:
            "gamecontroller.fill"
        case .mindfulness:
            "circle.hexagongrid"
        case .reading:
            "book.closed.fill"
        case .custom:
            "app.badge"
        case .unknown:
            "moon.fill"
        }
    }
}

@MainActor
final class FocusModeMonitor {
    static let shared = FocusModeMonitor()

    private let center = DistributedNotificationCenter.default()
    private var enabledObserver: NSObjectProtocol?
    private var disabledObserver: NSObjectProtocol?
    private var lastPresentation = FocusModePresentation(title: "Focus", symbol: "moon.fill")

    private init() {}

    func start() {
        guard enabledObserver == nil, disabledObserver == nil else { return }

        enabledObserver = center.addObserver(
            forName: .focusModeEnabled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification, isActive: true)
        }

        disabledObserver = center.addObserver(
            forName: .focusModeDisabled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handle(notification, isActive: false)
        }
    }

    private func handle(_ notification: Notification, isActive: Bool) {
        guard Defaults[.hudReplacement], Defaults[.showFocusIndicator] else { return }

        let metadata = extractMetadata(from: notification)
        let presentation = presentation(for: metadata.identifier, name: metadata.name)
        let currentPresentation = isActive ? presentation : fallbackPresentation(for: presentation)

        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .focus,
            duration: 1.4,
            value: isActive ? 1 : 0,
            icon: currentPresentation.symbol,
            label: currentPresentation.title
        )

        if isActive {
            lastPresentation = currentPresentation
        } else {
            lastPresentation = FocusModePresentation(title: "Focus", symbol: "moon.fill")
        }
    }

    private func fallbackPresentation(for presentation: FocusModePresentation) -> FocusModePresentation {
        if presentation.title != "Focus" || presentation.symbol != "moon.fill" {
            return presentation
        }

        return lastPresentation
    }

    private func presentation(for identifier: String?, name: String?) -> FocusModePresentation {
        let kind = FocusModeKind(identifier: identifier, name: name)
        let title = normalizedString(name) ?? kind.defaultTitle
        let symbol = customSymbol(from: identifier) ?? kind.symbolName
        return FocusModePresentation(title: title, symbol: symbol)
    }

    private func extractMetadata(from notification: Notification) -> (identifier: String?, name: String?) {
        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "FocusModeUUID",
            "focusModeUUID",
            "modeIdentifier",
            "identifier",
            "Identifier",
            "UUID",
            "uuid",
        ]
        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "activityDisplayName",
            "displayName",
            "name",
            "Name",
        ]
        let objectSelectors = [
            "mode",
            "details",
            "modeConfiguration",
            "activeModeConfiguration",
            "activeModeAssertionMetadata",
        ]

        let candidates = [notification.userInfo, notification.object].compactMap(\.self)

        var identifier: String?
        var name: String?

        for candidate in candidates {
            if identifier == nil {
                identifier = firstString(
                    in: candidate,
                    keys: identifierKeys,
                    stringSelectors: ["modeIdentifier", "identifier"],
                    objectSelectors: objectSelectors,
                    preferIdentifier: true
                )
            }

            if name == nil {
                name = firstString(
                    in: candidate,
                    keys: nameKeys,
                    stringSelectors: ["name", "displayName", "activityDisplayName"],
                    objectSelectors: objectSelectors,
                    preferIdentifier: false
                )
            }
        }

        return (identifier, name)
    }

    private func firstString(
        in value: Any,
        keys: [String],
        stringSelectors: [String],
        objectSelectors: [String],
        preferIdentifier: Bool
    ) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let direct = dictionary[key],
                   let string = directString(from: direct, preferIdentifier: preferIdentifier)
                {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let string = firstString(
                    in: nestedValue,
                    keys: keys,
                    stringSelectors: stringSelectors,
                    objectSelectors: objectSelectors,
                    preferIdentifier: preferIdentifier
                ) {
                    return string
                }
            }

            return nil
        }

        if let array = value as? [Any] {
            for element in array {
                if let string = firstString(
                    in: element,
                    keys: keys,
                    stringSelectors: stringSelectors,
                    objectSelectors: objectSelectors,
                    preferIdentifier: preferIdentifier
                ) {
                    return string
                }
            }

            return nil
        }

        if let decodedPayload = decodedPayload(from: value) {
            return firstString(
                in: decodedPayload,
                keys: keys,
                stringSelectors: stringSelectors,
                objectSelectors: objectSelectors,
                preferIdentifier: preferIdentifier
            )
        }

        if let object = value as? NSObject {
            for selectorName in stringSelectors {
                if let string = stringValue(from: object, selectorName: selectorName) {
                    return string
                }
            }

            for selectorName in objectSelectors {
                if let nestedObject = objectValue(from: object, selectorName: selectorName),
                   let string = firstString(
                       in: nestedObject,
                       keys: keys,
                       stringSelectors: stringSelectors,
                       objectSelectors: objectSelectors,
                       preferIdentifier: preferIdentifier
                   )
                {
                    return string
                }
            }
        }

        return directString(from: value, preferIdentifier: preferIdentifier)
    }

    private func directString(from value: Any, preferIdentifier: Bool) -> String? {
        if let string = value as? String {
            if preferIdentifier {
                return inferredIdentifier(from: string) ?? normalizedString(string)
            }

            return normalizedString(string)
        }

        if let number = value as? NSNumber {
            return normalizedString(number.stringValue)
        }

        if let uuid = value as? UUID {
            return uuid.uuidString
        }

        if let uuid = value as? NSUUID {
            return uuid.uuidString
        }

        return nil
    }

    private func decodedPayload(from value: Any) -> Any? {
        let data: Data? = if let rawData = value as? Data {
            rawData
        } else if let rawData = value as? NSData {
            rawData as Data
        } else {
            nil
        }

        guard let data, !data.isEmpty else { return nil }

        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return plist
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return json
        }

        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        return nil
    }

    private func stringValue(from object: NSObject, selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue()
        else {
            return nil
        }

        return directString(from: value, preferIdentifier: selectorName.localizedCaseInsensitiveContains("identifier"))
    }

    private func objectValue(from object: NSObject, selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue()
        else {
            return nil
        }

        return value as? NSObject
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func customSymbol(from identifier: String?) -> String? {
        guard let identifier = normalizedString(identifier)?.lowercased() else { return nil }

        let prefix = "com.apple.donotdisturb.mode."
        guard identifier.hasPrefix(prefix) else { return nil }

        let symbol = String(identifier.dropFirst(prefix.count))
        guard !symbol.isEmpty, symbol != "default" else { return nil }

        return symbol
    }

    private func inferredIdentifier(from value: String) -> String? {
        guard let range = value.range(
            of: #"com\.apple\.[A-Za-z0-9._-]+"#,
            options: .regularExpression
        ) else {
            return nil
        }

        return normalizedString(String(value[range]))
    }
}

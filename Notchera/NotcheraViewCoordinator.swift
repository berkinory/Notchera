import AppKit
import Carbon
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case capsLock
    case inputSource
    case focus
    case recording
    case battery
    case hudEnabled
    case download
}

struct HUDState: Equatable {
    var show: Bool = false
    var type: SneakContentType = .volume
    var value: CGFloat = 0
    var icon: String = ""
    var label: String = ""
}

struct SharedHUDState: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class NotcheraViewCoordinator: ObservableObject {
    static let shared = NotcheraViewCoordinator()

    @AppStorage("lastView") private var lastViewRaw: String = NotchViews.home.rawValue

    @Published var currentView: NotchViews = .home {
        didSet {
            lastViewRaw = currentView.rawValue
        }
    }

    @Published var helloAnimationRunning: Bool = false
    private let hudHidePollInterval: Duration = .milliseconds(100)
    private var hudEnableTask: Task<Void, Never>?
    private var hudHideTask: Task<Void, Never>?
    private var hudHideDeadline: Date = .distantPast

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if currentView != .shelf {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }

    @Default(.hudReplacement) var hudReplacement: Bool

    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?

    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?
    private var shelfStateCancellable: AnyCancellable?

    private var rememberedView: NotchViews? {
        guard openLastTabByDefault,
              let rememberedView = NotchViews(rawValue: lastViewRaw)
        else {
            return nil
        }

        return rememberedView
    }

    var preferredExpandedView: NotchViews {
        rememberedView ?? .home
    }

    private init() {
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID
            {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            preferredScreenUUID = NSScreen.main?.displayUUID
        }

        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        currentView = preferredExpandedView

        InputSourceMonitor.shared.start()
        FocusModeMonitor.shared.start()

        shelfStateCancellable = ShelfStateViewModel.shared.$items
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEmpty in
                guard let self, isEmpty, self.currentView == .shelf else { return }
                self.currentView = .home
            }

        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .dropFirst()
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                                self.toggleHUD(status: true, type: .hudEnabled, duration: 1.6, value: 1)
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                        self.clearHUDState()
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    Defaults[.hudReplacement] = false
                } else {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }
    }

    @objc func hudEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        guard let payload = notification.userInfo?.first?.value as? Data else { return }

        if let decodedData = try? decoder.decode(
            SharedHUDState.self, from: payload
        ) {
            let contentType =
                decodedData.type == "brightness"
                    ? SneakContentType.brightness
                    : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                    ? SneakContentType.backlight
                    : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleHUD(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    func toggleHUD(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        label: String = ""
    ) {
        if status, !Defaults[.hudReplacement] {
            return
        }

        if status, !isIndicatorEnabled(for: type) {
            return
        }

        let nextState = HUDState(
            show: status,
            type: type,
            value: type == .recording ? (value > 0 ? 1 : 0) : value,
            icon: icon,
            label: label
        )

        if status {
            if hud == nextState {
                hudHideDeadline = Date().addingTimeInterval(duration)
                scheduleHUDHideIfNeeded()
                return
            }

            hudHideDeadline = Date().addingTimeInterval(duration)
            applyHUDState(nextState)
            scheduleHUDHideIfNeeded()
            return
        }

        clearHUDTasks()
        applyHUDState(nextState)
    }

    @Published var hud: HUDState = .init()

    private func scheduleHUDHideIfNeeded() {
        guard hudHideTask == nil else { return }

        hudHideTask = Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.hudHideTask = nil
            }

            while !Task.isCancelled {
                if hudHideDeadline.timeIntervalSinceNow <= 0 {
                    break
                }

                try? await Task.sleep(for: hudHidePollInterval)
            }

            guard !Task.isCancelled else { return }

            let currentHUD = hud
            clearHUDTasks()
            applyHUDState(
                HUDState(
                    show: false,
                    type: currentHUD.type,
                    value: currentHUD.value,
                    icon: currentHUD.icon,
                    label: currentHUD.label
                )
            )
        }
    }

    private func isIndicatorEnabled(for type: SneakContentType) -> Bool {
        switch type {
        case .volume:
            Defaults[.showVolumeIndicator]
        case .brightness:
            Defaults[.showBrightnessIndicator]
        case .backlight:
            Defaults[.showBacklightIndicator]
        case .capsLock:
            Defaults[.showCapsLockIndicator]
        case .inputSource:
            Defaults[.showInputSourceIndicator]
        case .focus:
            Defaults[.showFocusIndicator]
        case .recording:
            Defaults[.enableScreenRecordingDetection]
        case .battery:
            Defaults[.showPowerStatusNotifications]
        case .hudEnabled, .download:
            true
        }
    }

    private func applyHUDState(_ state: HUDState) {
        guard hud != state else { return }

        let shouldAnimate =
            hud.show != state.show ||
            hud.type != state.type ||
            hud.icon != state.icon ||
            hud.label != state.label

        if shouldAnimate {
            withAnimation(.smooth) {
                hud = state
            }
        } else {
            hud = state
        }
    }

    private func clearHUDTasks() {
        hudHideDeadline = .distantPast
        hudHideTask?.cancel()
        hudHideTask = nil
    }

    private func clearHUDState() {
        clearHUDTasks()
        hud = .init()
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        if status, (!Defaults[.hudReplacement] || !isIndicatorEnabled(for: type)) {
            return
        }

        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self, !Task.isCancelled else { return }
                    toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    func prepareViewForOpen() {
        currentView = preferredExpandedView
    }

    func showShelf() {
        currentView = .shelf
    }

    func resetViewAfterClose() {
        currentView = preferredExpandedView
    }

    func showEmpty() {
        currentView = .home
    }
}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
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
private final class FocusModeMonitor {
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
            "uuid"
        ]
        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "activityDisplayName",
            "displayName",
            "name",
            "Name"
        ]
        let objectSelectors = [
            "mode",
            "details",
            "modeConfiguration",
            "activeModeConfiguration",
            "activeModeAssertionMetadata"
        ]

        let candidates = [notification.userInfo, notification.object].compactMap { $0 }

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
                   let string = directString(from: direct, preferIdentifier: preferIdentifier) {
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
                   ) {
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
        let data: Data?

        if let rawData = value as? Data {
            data = rawData
        } else if let rawData = value as? NSData {
            data = rawData as Data
        } else {
            data = nil
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
              let value = object.perform(selector)?.takeUnretainedValue() else {
            return nil
        }

        return directString(from: value, preferIdentifier: selectorName.localizedCaseInsensitiveContains("identifier"))
    }

    private func objectValue(from object: NSObject, selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() else {
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

private final class InputSourceMonitor {
    static let shared = InputSourceMonitor()

    private var observer: NSObjectProtocol?
    private var currentLabel = ""

    private init() {}

    func start() {
        guard observer == nil else { return }

        currentLabel = Self.currentInputSourceLabel()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleInputSourceChange()
            }
        }
    }

    @MainActor
    private func handleInputSourceChange() {
        let nextLabel = Self.currentInputSourceLabel()
        guard !nextLabel.isEmpty, nextLabel != currentLabel else { return }

        currentLabel = nextLabel
        guard Defaults[.showInputSourceIndicator] else { return }

        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .inputSource,
            duration: 1.0,
            value: 1,
            icon: "translate",
            label: nextLabel
        )
    }

    private static func currentInputSourceLabel() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

        if let languagesPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let languages = Unmanaged<CFArray>.fromOpaque(languagesPointer).takeUnretainedValue() as NSArray
            if let language = languages.firstObject as? String {
                let normalized = normalizeLanguageCode(language)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        if let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPointer).takeUnretainedValue() as String
            let normalized = normalizeSourceID(sourceID)
            if !normalized.isEmpty {
                return normalized
            }
        }

        if let localizedNamePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let localizedName = Unmanaged<CFString>.fromOpaque(localizedNamePointer).takeUnretainedValue() as String
            let trimmedName = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                return trimmedName.prefix(4).uppercased()
            }
        }

        return ""
    }

    private static func normalizeLanguageCode(_ language: String) -> String {
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.isEmpty else { return "" }

        let locale = Locale(identifier: trimmedLanguage)
        let baseCode = locale.language.languageCode?.identifier ?? trimmedLanguage
        return String(baseCode.prefix(4)).uppercased()
    }

    private static func normalizeSourceID(_ sourceID: String) -> String {
        let candidate = sourceID
            .split(separator: ".")
            .reversed()
            .first(where: { $0.rangeOfCharacter(from: .letters) != nil })?
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .uppercased() ?? ""

        return String(candidate.prefix(4))
    }
}

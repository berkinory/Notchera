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
    case download
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

        let red = Double((value & 0xFF000000) >> 24) / 255
        let green = Double((value & 0x00FF0000) >> 16) / 255
        let blue = Double((value & 0x0000FF00) >> 8) / 255
        let alpha = Double(value & 0x000000FF) / 255
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
            guard !suppressRememberedViewUpdate else {
                suppressRememberedViewUpdate = false
                return
            }

            lastViewRaw = currentView.rawValue
        }
    }

    @Published var helloAnimationRunning: Bool = false
    @Published var clipboardKeyboardNavigationActive: Bool = false
    @Published var notchKeyboardDismissActive: Bool = false
    @Published var commandPaletteModule: CommandPaletteModule = .appLauncher
    @Published var commandPaletteQuery: String = ""
    @Published var clipboardSearchQuery: String = ""
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
    private var externalHUDObserver: NSObjectProtocol?
    private var hudReplacementCancellable: AnyCancellable?
    private var shelfStateCancellable: AnyCancellable?
    private var suppressRememberedViewUpdate = false
    private var lastExternalHUDRequestAt: Date = .distantPast

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

    func showViewWithoutRemembering(_ view: NotchViews) {
        suppressRememberedViewUpdate = true
        currentView = view
    }

    func prepareCommandPalette(module: CommandPaletteModule, rememberView: Bool = true) {
        commandPaletteModule = module
        commandPaletteQuery = ""

        if rememberView {
            currentView = .commandPalette
        } else {
            showViewWithoutRemembering(.commandPalette)
        }
    }

    func showCommandPaletteAppLauncher() {
        commandPaletteModule = .appLauncher
        commandPaletteQuery = ""
    }

    func showCommandPaletteClipboard() {
        commandPaletteModule = .clipboard
        commandPaletteQuery = ""
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
        startExternalHUDListener()

        DispatchQueue.main.async {
            BluetoothAudioMonitor.shared.start()
        }

        shelfStateCancellable = ShelfStateViewModel.shared.$items
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEmpty in
                guard let self, isEmpty, currentView == .shelf else { return }
                currentView = .home
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

    private func startExternalHUDListener() {
        guard externalHUDObserver == nil else { return }

        externalHUDObserver = DistributedNotificationCenter.default().addObserver(
            forName: .externalHUDRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleExternalHUDNotification(notification)
        }
    }

    private func handleExternalHUDNotification(_ notification: Notification) {
        guard let payload = externalHUDPayload(from: notification),
              let data = payload.data(using: .utf8),
              let request = try? JSONDecoder().decode(ExternalHUDRequest.self, from: data),
              let normalizedRequest = request.normalized()
        else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastExternalHUDRequestAt) >= 0.05 else {
            return
        }

        guard !(hud.show && hud.type == .custom && hud.custom == normalizedRequest) else {
            return
        }

        lastExternalHUDRequestAt = now

        toggleHUD(
            status: true,
            type: .custom,
            duration: normalizedRequest.duration,
            custom: normalizedRequest
        )
    }

    private func externalHUDPayload(from notification: Notification) -> String? {
        if let payload = notification.userInfo?["payload"] as? String {
            return payload
        }

        if let payload = notification.userInfo?["payload"] as? Data {
            return String(data: payload, encoding: .utf8)
        }

        return notification.object as? String
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
        label: String = "",
        custom: ExternalHUDRequest? = nil
    ) {
        if status, type != .custom, !Defaults[.hudReplacement] {
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
            label: label,
            duration: duration,
            custom: type == .custom ? custom : nil
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
                    label: currentHUD.label,
                    duration: currentHUD.duration,
                    custom: currentHUD.custom
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
        case .bluetoothAudio:
            Defaults[.showBluetoothAudioIndicator]
        case .recording:
            Defaults[.enableScreenRecordingDetection]
        case .battery:
            Defaults[.showPowerStatusNotifications]
        case .hudEnabled, .download, .custom:
            true
        }
    }

    private func applyHUDState(_ state: HUDState) {
        guard hud != state else { return }

        let shouldAnimate =
            hud.show != state.show ||
            hud.type != state.type ||
            hud.icon != state.icon ||
            hud.label != state.label ||
            (hud.type == .custom && hud.custom?.animationKey != state.custom?.animationKey)

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
        if status, !Defaults[.hudReplacement] || !isIndicatorEnabled(for: type) {
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
                let duration: TimeInterval =
                    expandingView.type == .download ? 1.5 :
                    expandingView.type == .battery ? 2.5 :
                    2.5
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

private struct BluetoothAudioPresentation {
    let title: String
    let symbol: String
}

private enum BluetoothAudioKind {
    case speaker
    case headphones
    case generic

    var symbolName: String {
        switch self {
        case .speaker:
            "hifispeaker.fill"
        case .headphones:
            "headphones"
        case .generic:
            "airpods"
        }
    }
}

@MainActor
private final class BluetoothAudioMonitor: NSObject {
    static let shared = BluetoothAudioMonitor()

    private let bluetoothPreferencesSuite = "/Library/Preferences/com.apple.Bluetooth"
    private let appleVendorID: UInt16 = 0x05AC
    private let airPodsSymbolByProductID: [UInt16: String] = [
        0x200F: "airpods",
        0x2013: "airpods.gen3",
        0x2019: "airpods.gen4",
        0x201B: "airpods.gen4",
        0x200A: "airpods.max",
        0x201F: "airpods.max",
        0x200E: "airpods.pro",
        0x2014: "airpods.pro",
        0x2024: "airpods.pro",
        0x2027: "airpods.pro",
    ]

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var knownDeviceKeys: Set<String> = []
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.5
    private var lastPresentedAt: [String: Date] = [:]
    private let presentationCooldown: TimeInterval = 2
    private var startupSuppressedDeviceKey: String?
    private var startupSuppressionDeadline: Date = .distantPast

    override private init() {
        super.init()
    }

    func start() {
        guard connectNotification == nil else { return }

        let initialDevices = connectedAudioDevices()
        knownDeviceKeys = Set(initialDevices.map(deviceKey(for:)))
        startupSuppressedDeviceKey = currentBluetoothOutputDeviceKey(in: initialDevices)
        startupSuppressionDeadline = Date().addingTimeInterval(5)

        refreshDisconnectNotifications(for: initialDevices)
        startPolling()
        startAudioRouteMonitoring()

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
    }

    @objc
    private func bluetoothDeviceConnected(
        _: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard isAudioDevice(device) else { return }

        registerDisconnectNotification(for: device)
        syncConnectedDevices(showHUDForNewDevices: false)
        present(device)
    }

    @objc
    private func bluetoothDeviceDisconnected(
        _: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        unregisterDisconnectNotification(for: device)
        syncConnectedDevices(showHUDForNewDevices: false)
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncConnectedDevices(showHUDForNewDevices: true)
            }
        }
    }

    private func startAudioRouteMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleAudioRouteChange()
            }
        }
    }

    private func handleAudioRouteChange() {
        let devices = connectedAudioDevices()

        if let outputDeviceKey = currentBluetoothOutputDeviceKey(in: devices) {
            if shouldSuppressStartupPresentation(for: outputDeviceKey) {
                return
            }

            if let matchingDevice = devices.first(where: { deviceKey(for: $0) == outputDeviceKey }) {
                present(matchingDevice)
            }
            return
        }

        if Date() >= startupSuppressionDeadline {
            startupSuppressedDeviceKey = nil
        }
    }

    private func syncConnectedDevices(showHUDForNewDevices: Bool) {
        let devices = connectedAudioDevices()
        let nextKeys = Set(devices.map(deviceKey(for:)))
        let newDevices = devices.filter { !knownDeviceKeys.contains(deviceKey(for: $0)) }
        let staleKeys = knownDeviceKeys.subtracting(nextKeys)

        knownDeviceKeys = nextKeys
        for staleKey in staleKeys {
            lastPresentedAt.removeValue(forKey: staleKey)
        }

        refreshDisconnectNotifications(for: devices)

        guard showHUDForNewDevices else { return }

        for device in newDevices {
            present(device)
        }
    }

    private func present(_ device: IOBluetoothDevice) {
        guard Defaults[.hudReplacement], Defaults[.showBluetoothAudioIndicator] else { return }

        let key = deviceKey(for: device)
        if shouldSuppressStartupPresentation(for: key) {
            return
        }

        let now = Date()
        if let lastPresentedAt = lastPresentedAt[key],
           now.timeIntervalSince(lastPresentedAt) < presentationCooldown
        {
            return
        }

        lastPresentedAt[key] = now

        let presentation = presentation(for: device)
        NotcheraViewCoordinator.shared.toggleHUD(
            status: true,
            type: .bluetoothAudio,
            duration: 2.5,
            value: 1,
            icon: presentation.symbol,
            label: presentation.title
        )
    }

    private func connectedAudioDevices() -> [IOBluetoothDevice] {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return pairedDevices.filter { $0.isConnected() && isAudioDevice($0) }
    }

    private func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        let audioSink = IOBluetoothSDPUUID(uuid16: 0x110B)
        let headset = IOBluetoothSDPUUID(uuid16: 0x1108)
        let handsfree = IOBluetoothSDPUUID(uuid16: 0x111E)

        if device.getServiceRecord(for: audioSink) != nil {
            return true
        }

        if device.getServiceRecord(for: headset) != nil {
            return true
        }

        if device.getServiceRecord(for: handsfree) != nil {
            return true
        }

        let majorClass = (device.classOfDevice >> 8) & 0x1F
        return majorClass == 0x04
    }

    private func presentation(for device: IOBluetoothDevice) -> BluetoothAudioPresentation {
        let title = normalizedDeviceName(device.name) ?? "Bluetooth Audio"
        let fallbackSymbol = genericSymbol(for: device, name: title)
        let preferredSymbol = airPodsSymbol(for: device, name: title) ?? fallbackSymbol
        let symbol = resolvedSymbolName(preferredSymbol, fallback: fallbackSymbol)
        return BluetoothAudioPresentation(title: title, symbol: symbol)
    }

    private func refreshDisconnectNotifications(for devices: [IOBluetoothDevice]) {
        let activeKeys = Set(devices.map(deviceKey(for:)))

        for device in devices {
            registerDisconnectNotification(for: device)
        }

        let staleKeys = disconnectNotifications.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            disconnectNotifications[key]?.unregister()
            disconnectNotifications.removeValue(forKey: key)
        }
    }

    private func registerDisconnectNotification(for device: IOBluetoothDevice) {
        let key = deviceKey(for: device)
        guard disconnectNotifications[key] == nil else { return }

        disconnectNotifications[key] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDeviceDisconnected(_:device:))
        )
    }

    private func unregisterDisconnectNotification(for device: IOBluetoothDevice) {
        let key = deviceKey(for: device)
        disconnectNotifications[key]?.unregister()
        disconnectNotifications.removeValue(forKey: key)
    }

    private func currentBluetoothOutputDeviceKey(in devices: [IOBluetoothDevice]) -> String? {
        let outputDeviceID = currentOutputDeviceID()
        guard outputDeviceID != kAudioObjectUnknown,
              isBluetoothOutputDevice(outputDeviceID),
              let outputDeviceName = outputDeviceName(outputDeviceID)
        else {
            return nil
        }

        if let matchingDevice = devices.first(where: {
            normalizedName($0.name) == normalizedName(outputDeviceName)
        }) {
            return deviceKey(for: matchingDevice)
        }

        if devices.count == 1, let onlyDevice = devices.first {
            return deviceKey(for: onlyDevice)
        }

        return nil
    }

    private func shouldSuppressStartupPresentation(for deviceKey: String) -> Bool {
        if Date() >= startupSuppressionDeadline {
            startupSuppressedDeviceKey = nil
            return false
        }

        guard startupSuppressedDeviceKey == deviceKey else { return false }
        return true
    }

    private func currentOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private func isBluetoothOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &transportType
        )

        guard status == noErr else { return false }

        return transportType == kAudioDeviceTransportTypeBluetooth ||
            transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private func outputDeviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr else { return nil }
        let result = name as String
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    private func normalizedName(_ value: String?) -> String {
        guard let value else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func genericSymbol(for device: IOBluetoothDevice, name: String) -> String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("speaker") || normalizedName.contains("boombox") {
            return BluetoothAudioKind.speaker.symbolName
        }

        if normalizedName.contains("headset") ||
            normalizedName.contains("hands-free") ||
            normalizedName.contains("headphone") ||
            normalizedName.contains("earbuds") ||
            normalizedName.contains("buds")
        {
            return BluetoothAudioKind.headphones.symbolName
        }

        let minorClass = (device.classOfDevice >> 2) & 0x3F
        switch minorClass {
        case 0x01, 0x02, 0x06:
            return BluetoothAudioKind.headphones.symbolName
        case 0x08, 0x0C:
            return BluetoothAudioKind.speaker.symbolName
        default:
            return BluetoothAudioKind.generic.symbolName
        }
    }

    private func airPodsSymbol(for device: IOBluetoothDevice, name: String) -> String? {
        if let productID = airPodsProductID(for: device),
           let symbol = airPodsSymbolByProductID[productID]
        {
            return symbol
        }

        let normalizedName = name.lowercased()
        guard normalizedName.contains("airpods") else { return nil }

        if normalizedName.contains("max") {
            return "airpods.max"
        }

        if normalizedName.contains("pro") {
            return "airpods.pro"
        }

        if normalizedName.contains("gen 4") ||
            normalizedName.contains("gen4") ||
            normalizedName.contains("4th") ||
            normalizedName.contains("airpods 4") ||
            normalizedName.contains("airpods4")
        {
            return "airpods.gen4"
        }

        if normalizedName.contains("gen 3") ||
            normalizedName.contains("gen3") ||
            normalizedName.contains("3rd") ||
            normalizedName.contains("third") ||
            normalizedName.contains("airpods 3") ||
            normalizedName.contains("airpods3")
        {
            return "airpods.gen3"
        }

        return "airpods"
    }

    private func airPodsProductID(for device: IOBluetoothDevice) -> UInt16? {
        guard let payload = bluetoothCachePayload(for: device) else { return nil }

        let vendorKeys = [
            "VendorID",
            "vendor_id",
            "vendorID",
            "device_vendorID",
            "DeviceVendorID",
            "VendorId",
            "Vendor ID",
        ]
        let productKeys = [
            "ProductID",
            "product_id",
            "productID",
            "device_productID",
            "DeviceProductID",
            "ProductId",
            "Product ID",
        ]

        let vendorID = extractUInt16(from: payload, keys: vendorKeys)
        let productID = extractUInt16(from: payload, keys: productKeys)

        guard let productID, airPodsSymbolByProductID[productID] != nil else { return nil }
        guard vendorID == nil || vendorID == appleVendorID else { return nil }
        return productID
    }

    private func bluetoothCachePayload(for device: IOBluetoothDevice) -> [String: Any]? {
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite),
              let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any]
        else {
            return nil
        }

        let targetAddress = normalizedBluetoothAddress(device.addressString)
        guard !targetAddress.isEmpty else { return nil }

        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }

            if normalizedBluetoothAddress(key) == targetAddress {
                return payload
            }

            if let payloadAddress = normalizedBluetoothAddress(from: payload["DeviceAddress"])
                ?? normalizedBluetoothAddress(from: payload["Address"])
                ?? normalizedBluetoothAddress(from: payload["BD_ADDR"])
                ?? normalizedBluetoothAddress(from: payload["device_address"]),
                payloadAddress == targetAddress
            {
                return payload
            }
        }

        return nil
    }

    private func extractUInt16(from payload: [String: Any], keys: [String]) -> UInt16? {
        for key in keys {
            guard let rawValue = payload[key] else { continue }

            if let number = rawValue as? NSNumber {
                return UInt16(truncatingIfNeeded: number.uint16Value)
            }

            if let intValue = rawValue as? Int {
                return UInt16(truncatingIfNeeded: intValue)
            }

            if let stringValue = rawValue as? String {
                let normalizedValue = stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if normalizedValue.hasPrefix("0x"),
                   let parsedValue = UInt16(normalizedValue.dropFirst(2), radix: 16)
                {
                    return parsedValue
                }

                if let parsedValue = UInt16(normalizedValue, radix: 10) {
                    return parsedValue
                }
            }
        }

        return nil
    }

    private func resolvedSymbolName(_ symbol: String, fallback: String) -> String {
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            return symbol
        }

        return NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil
            ? fallback
            : BluetoothAudioKind.generic.symbolName
    }

    private func deviceKey(for device: IOBluetoothDevice) -> String {
        let address = normalizedBluetoothAddress(device.addressString)
        if !address.isEmpty {
            return address
        }

        let name = normalizedDeviceName(device.name) ?? "unknown"
        return name.lowercased()
    }

    private func normalizedDeviceName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func normalizedBluetoothAddress(from value: Any?) -> String? {
        if let stringValue = value as? String {
            let normalizedValue = normalizedBluetoothAddress(stringValue)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }

        return nil
    }

    private func normalizedBluetoothAddress(_ value: String?) -> String {
        guard let value else { return "" }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
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

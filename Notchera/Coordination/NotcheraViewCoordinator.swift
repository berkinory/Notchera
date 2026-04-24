import AppKit
import Carbon
import Combine
import CoreAudio
import Defaults
import IOBluetooth
import SwiftUI

class NotcheraViewCoordinator: ObservableObject {
    static let shared = NotcheraViewCoordinator()

    @AppStorage("lastView") private var lastViewRaw: String = NotchViews.home.rawValue

    @Published var currentView: NotchViews = .home {
        didSet {
            resetTransientInputIfNeeded(for: currentView)

            guard !suppressRememberedViewUpdate else {
                suppressRememberedViewUpdate = false
                return
            }

            lastViewRaw = currentView.rawValue
        }
    }

    @Published var clipboardKeyboardNavigationActive: Bool = false
    @Published var notchKeyboardDismissActive: Bool = false
    @Published var isScreenLocked: Bool = false
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

    @AppStorage("hideTabButtons") var hideTabButtons: Bool = false

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false

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
    private var calendarVisibilityCancellable: AnyCancellable?
    private var suppressRememberedViewUpdate = false
    private var lastExternalHUDRequestAt: Date = .distantPast

    private var rememberedView: NotchViews? {
        guard openLastTabByDefault,
              let rememberedView = NotchViews(rawValue: lastViewRaw)
        else {
            return nil
        }

        if rememberedView == .calendar, !Defaults[.enableCalendar] {
            return nil
        }

        return rememberedView
    }

    var preferredExpandedView: NotchViews {
        rememberedView ?? .home
    }

    private func resetTransientInputIfNeeded(for view: NotchViews) {
        switch view {
        case .commandPalette:
            commandPaletteQuery = ""
        case .clipboard:
            clipboardSearchQuery = ""
        default:
            break
        }
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

    private init() {
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID
            {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                preferredScreenUUID = NSScreen.screens.first(where: { $0.isBuiltInDisplay })?.displayUUID ?? NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to built-in display")
            }
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            preferredScreenUUID = NSScreen.screens.first(where: { $0.isBuiltInDisplay })?.displayUUID ?? NSScreen.main?.displayUUID
        }

        selectedScreenUUID = preferredScreenUUID ?? NSScreen.screens.first(where: { $0.isBuiltInDisplay })?.displayUUID ?? NSScreen.main?.displayUUID ?? ""
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

        calendarVisibilityCancellable = Defaults.publisher(.enableCalendar)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self, !isEnabled, currentView == .calendar else { return }
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
            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    if !firstLaunch {
                        Defaults[.hudReplacement] = false
                    }
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
        case .hudEnabled, .custom:
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
        value: CGFloat = 0
    ) {
        if status, !Defaults[.hudReplacement] || !isIndicatorEnabled(for: type) {
            return
        }

        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval =
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

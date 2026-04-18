import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case capsLock
    case mic
    case recording
    case battery
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
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

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

    @Published var optionKeyPressed: Bool = true
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
                    : decodedData.type == "mic"
                    ? SneakContentType.mic : SneakContentType.brightness

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

        if type == .mic {
            currentMicStatus = value == 1
        }

        let nextState = HUDState(
            show: status,
            type: type,
            value: type == .mic || type == .recording ? (value > 0 ? 1 : 0) : value,
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
            applyHUDState(HUDState(show: false, type: currentHUD.type, value: currentHUD.value, icon: currentHUD.icon, label: currentHUD.label))
        }
    }

    private func applyHUDState(_ state: HUDState) {
        guard hud != state else { return }

        let shouldAnimate = hud.show != state.show || hud.type != state.type || hud.icon != state.icon || hud.label != state.label

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

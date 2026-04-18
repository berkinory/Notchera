import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )

        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("notchera", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Notchera") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:]
    var viewModels: [String: NotcheraViewModel] = [:]
    var window: NSWindow?
    let vm: NotcheraViewModel = .init()
    let musicManager = MusicManager.shared
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var collapsedHoverStartDates: [String: Date] = [:]
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:]
    private var windowVisibilityObservers: [String: AnyCancellable] = [:]
    private var appCancellables: Set<AnyCancellable> = []

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        timer?.invalidate()
        timer = nil
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        ScreenRecordingManager.shared.stopMonitoring()
    }

    @MainActor
    func onScreenLocked(_: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }

    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                if let skyWindow = window as? NotcheraSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? NotcheraSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }

    @MainActor
    private func disableSkyLightOnAllWindows() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    for window in self.windows.values {
                        if let skyWindow = window as? NotcheraSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? NotcheraSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]

        if shouldCleanupMulti {
            for window in windows.values {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
            windowVisibilityObservers.removeAll()
            collapsedHoverStartDates.removeAll()
        } else if let window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            windowVisibilityObservers.removeAll()
            collapsedHoverStartDates.removeAll()
            self.window = nil
        }
    }

    @MainActor
    private func updateWindowVisibility(_ window: NSWindow, isHidden: Bool) {
        window.ignoresMouseEvents = isHidden
        window.alphaValue = isHidden ? 0 : 1

        if isHidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func bindWindowVisibility(_ window: NSWindow, viewModel: NotcheraViewModel, key: String) {
        windowVisibilityObservers[key] = viewModel.$hideOnClosed
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak window] shouldHide in
                guard let self, let window else { return }
                updateWindowVisibility(window, isHidden: shouldHide)
            }

        Task { @MainActor in
            self.updateWindowVisibility(window, isHidden: viewModel.hideOnClosed)
        }
    }

    private func collapsedHitTestWidth(for viewModel: NotcheraViewModel) -> CGFloat {
        var width = viewModel.closedNotchSize.width

        if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
           viewModel.notchState == .closed, Defaults[.showPowerStatusNotifications]
        {
            width = openNotchSize.width
        } else if !coordinator.expandingView.show,
                  viewModel.notchState == .closed,
                  musicManager.isPlaying || !musicManager.isPlayerIdle,
                  coordinator.musicLiveActivityEnabled,
                  !viewModel.hideOnClosed
        {
            width += (2 * max(0, viewModel.effectiveClosedNotchHeight - 12) + 20)
        }

        return width
    }

    private func collapsedInteractiveRect(for viewModel: NotcheraViewModel, on screen: NSScreen) -> CGRect {
        let width = collapsedHitTestWidth(for: viewModel)
        let height = max(viewModel.effectiveClosedNotchHeight + viewModel.chinHeight, 0)
        let baseRect = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        guard Defaults[.extendHoverArea] else { return baseRect }
        return baseRect.insetBy(dx: -16, dy: -10)
    }

    @MainActor
    private func updateWindowInteractivity() {
        let mouseLocation = NSEvent.mouseLocation

        if Defaults[.showOnAllDisplays] {
            for (uuid, window) in windows {
                guard let viewModel = viewModels[uuid], let screen = window.screen ?? NSScreen.screen(withUUID: uuid) else { continue }
                updateWindowInteractivity(window, viewModel: viewModel, screen: screen, key: uuid, mouseLocation: mouseLocation)
            }
        } else if let window {
            let key = vm.screenUUID ?? "main"
            let screen = window.screen
                ?? vm.screenUUID.flatMap(NSScreen.screen(withUUID:))
                ?? NSScreen.main
            guard let screen else { return }
            updateWindowInteractivity(window, viewModel: vm, screen: screen, key: key, mouseLocation: mouseLocation)
        }
    }

    @MainActor
    private func updateWindowInteractivity(_ window: NSWindow, viewModel: NotcheraViewModel, screen: NSScreen, key: String, mouseLocation: NSPoint) {
        guard window.isVisible, !viewModel.hideOnClosed else {
            collapsedHoverStartDates[key] = nil
            return
        }

        if viewModel.notchState == .open {
            collapsedHoverStartDates[key] = nil
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            return
        }

        let isPointerInside = collapsedInteractiveRect(for: viewModel, on: screen).contains(mouseLocation)
        window.ignoresMouseEvents = !isPointerInside

        guard Defaults[.openNotchOnHover], !coordinator.hud.show, !coordinator.firstLaunch else {
            collapsedHoverStartDates[key] = nil
            return
        }

        guard isPointerInside else {
            collapsedHoverStartDates[key] = nil
            return
        }

        if let hoverStart = collapsedHoverStartDates[key] {
            guard Date().timeIntervalSince(hoverStart) >= Defaults[.minimumHoverDuration] else { return }
            collapsedHoverStartDates[key] = nil
            viewModel.open()
        } else {
            collapsedHoverStartDates[key] = Date()
        }
    }

    private func cleanupDragDetectors() {
        for detector in dragDetectors.values {
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }

        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width

        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        let detector = DragDetector(notchRegion: notchRegion)

        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }

        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }

        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createNotcheraWindow(for _: NSScreen, with viewModel: NotcheraViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = NotcheraSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        bindWindowVisibility(window, viewModel: viewModel, key: viewModel.screenUUID ?? "main")
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha, !window.ignoresMouseEvents {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            )
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self, let window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.onScreenLocked(notification)
            }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.onScreenUnlocked(notification)
            }
        }

        if Defaults[.enableScreenRecordingDetection] {
            ScreenRecordingManager.shared.startMonitoring()
        }

        Defaults.publisher(.enableScreenRecordingDetection)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { isEnabled in
                if isEnabled {
                    ScreenRecordingManager.shared.startMonitoring()
                } else {
                    ScreenRecordingManager.shared.stopMonitoring()
                }
            }
            .store(in: &appCancellables)

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                closeNotchTask?.cancel()
                closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch {}
                    }
                    closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = vm
            let window = createNotcheraWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel
            )
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowInteractivity()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated,
                  Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "notchera", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
                || Set(currentScreens.compactMap(\.displayUUID))
                != Set(previousScreens?.compactMap(\.displayUUID) ?? [])
                || Set(currentScreens.map(\.frame)) != Set(previousScreens?.map(\.frame) ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap(\.displayUUID))

            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }

                if windows[uuid] == nil {
                    let viewModel = NotcheraViewModel(screenUUID: uuid)
                    let window = createNotcheraWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    updateWindowVisibility(window, isHidden: viewModel.hideOnClosed)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID
            {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createNotcheraWindow(for: selectedScreen, with: vm)
            }

            if let window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
                updateWindowVisibility(window, isHidden: vm.hideOnClosed)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                )
            )
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}

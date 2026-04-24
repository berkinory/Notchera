import ApplicationServices
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:]
    var viewModels: [String: NotcheraViewModel] = [:]
    var window: NSWindow?
    var lockScreenMediaWindow: NSWindow?
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
    private var mouseMoveMonitor: Any?
    private var mouseDragMonitor: Any?
    private var windowVisibilityObservers: [String: AnyCancellable] = [:]
    private var windowNotchStateObservers: [String: AnyCancellable] = [:]
    private var appCancellables: Set<AnyCancellable> = []
    private let windowInteractivityPollingInterval: TimeInterval = 1 / 15
    private weak var clipboardFocusedViewModel: NotcheraViewModel?
    private var keyboardDismissClickMonitor: Any?

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
        stopCursorMonitoring()
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        cleanupLockScreenMediaWindow()
        stopKeyboardDismissClickMonitoring()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        ScreenRecordingManager.shared.stopMonitoring()
        ClipboardHistoryManager.shared.stopMonitoring()
    }

    @MainActor
    func onScreenLocked(_: Notification) {
        isScreenLocked = true
        coordinator.isScreenLocked = true
        NotchKeyboardInterceptor.shared.stop()
        endClipboardKeyboardFocus(shouldCloseNotch: true)
        vm.close()
        viewModels.values.forEach { $0.close() }

        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
            updateLockScreenMediaWindowVisibility()
        }
    }

    @MainActor
    func onScreenUnlocked(_: Notification) {
        isScreenLocked = false
        coordinator.isScreenLocked = false
        cleanupLockScreenMediaWindow()
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
            windowNotchStateObservers.removeAll()
            collapsedHoverStartDates.removeAll()
        } else if let window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            windowVisibilityObservers.removeAll()
            windowNotchStateObservers.removeAll()
            collapsedHoverStartDates.removeAll()
            self.window = nil
        }
    }

    private var shouldShowLockScreenMediaWindow: Bool {
        isScreenLocked
            && Defaults[.showOnLockScreen]
            && coordinator.musicLiveActivityEnabled
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
    }

    @MainActor
    private func cleanupLockScreenMediaWindow() {
        lockScreenMediaWindow?.close()
        if let lockScreenMediaWindow {
            NotchSpaceManager.shared.notchSpace.windows.remove(lockScreenMediaWindow)
        }
        lockScreenMediaWindow = nil
    }

    @MainActor
    private func updateLockScreenMediaWindowVisibility() {
        guard shouldShowLockScreenMediaWindow else {
            cleanupLockScreenMediaWindow()
            return
        }

        let screen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
            ?? window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            cleanupLockScreenMediaWindow()
            return
        }

        if lockScreenMediaWindow == nil {
            lockScreenMediaWindow = createLockScreenMediaWindow(for: screen)
        }

        if let lockScreenMediaWindow {
            positionLockScreenMediaWindow(lockScreenMediaWindow, on: screen)
            lockScreenMediaWindow.orderFrontRegardless()
        }
    }

    @MainActor
    private func updateWindowVisibility(_ window: NSWindow, isHidden: Bool) {
        let interactionBlocked = isScreenLocked && Defaults[.showOnLockScreen]

        window.ignoresMouseEvents = isHidden || interactionBlocked
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

        windowNotchStateObservers[key] = viewModel.$notchState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                syncKeyboardSession()
            }

        Task { @MainActor in
            self.updateWindowVisibility(window, isHidden: viewModel.hideOnClosed)
            self.syncKeyboardSession()
        }
    }

    private func activeOpenNotchTarget() -> (window: NSWindow?, viewModel: NotcheraViewModel)? {
        if let clipboardFocusedViewModel, clipboardFocusedViewModel.notchState == .open {
            if Defaults[.showOnAllDisplays], let screenUUID = clipboardFocusedViewModel.screenUUID {
                return (windows[screenUUID], clipboardFocusedViewModel)
            }

            return (window, clipboardFocusedViewModel)
        }

        if Defaults[.showOnAllDisplays] {
            let mouseLocation = NSEvent.mouseLocation

            for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                guard let uuid = screen.displayUUID,
                      let viewModel = viewModels[uuid],
                      viewModel.notchState == .open
                else { continue }

                return (windows[uuid], viewModel)
            }

            if let openEntry = viewModels.first(where: { $0.value.notchState == .open }) {
                return (windows[openEntry.key], openEntry.value)
            }

            return nil
        }

        guard vm.notchState == .open else { return nil }
        return (window, vm)
    }

    private func syncKeyboardSession() {
        guard !(isScreenLocked && Defaults[.showOnLockScreen]) else {
            NotchKeyboardInterceptor.shared.stop()
            endClipboardKeyboardFocus()
            return
        }

        guard let target = activeOpenNotchTarget() else {
            endClipboardKeyboardFocus()
            return
        }

        if coordinator.currentView == .commandPalette || coordinator.currentView == .clipboard {
            coordinator.clipboardKeyboardNavigationActive = true
            coordinator.notchKeyboardDismissActive = true
            beginClipboardKeyboardFocus(on: target.window, viewModel: target.viewModel)
            return
        }

        guard coordinator.notchKeyboardDismissActive else { return }
        clipboardFocusedViewModel = target.viewModel

        guard let panel = target.window as? NotcheraSkyLightWindow else { return }
        panel.setClipboardKeyboardFocusEnabled(false)
        coordinator.clipboardKeyboardNavigationActive = false
        NotchKeyboardInterceptor.shared.start(mode: .dismissOnly)
        startKeyboardDismissClickMonitoring(for: panel, viewModel: target.viewModel)
    }

    private func collapsedHitTestWidth(for viewModel: NotcheraViewModel) -> CGFloat {
        var width = viewModel.closedNotchSize.width

        if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
           viewModel.notchState == .closed, Defaults[.hudReplacement], Defaults[.showPowerStatusNotifications]
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

    private func setupCursorMonitoring() {
        stopCursorMonitoring()

        let handler: @MainActor (NSEvent) -> Void = { [weak self] _ in
            self?.updateWindowInteractivity()
        }

        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { event in
            Task { @MainActor in
                handler(event)
            }
        }

        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { event in
            Task { @MainActor in
                handler(event)
            }
        }
    }

    private func stopCursorMonitoring() {
        for monitor in [mouseMoveMonitor, mouseDragMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        mouseMoveMonitor = nil
        mouseDragMonitor = nil
    }

    @MainActor
    private func updateWindowInteractivity() {
        guard !(isScreenLocked && Defaults[.showOnLockScreen]) else {
            collapsedHoverStartDates.removeAll()

            if Defaults[.showOnAllDisplays] {
                for window in windows.values {
                    window.ignoresMouseEvents = true
                }
            } else {
                window?.ignoresMouseEvents = true
            }

            return
        }

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
            if window.frame.contains(mouseLocation) {
                NSCursor.arrow.set()
            }
            return
        }

        let normalizedMouseLocation = CGPoint(
            x: mouseLocation.x,
            y: min(mouseLocation.y, screen.frame.maxY - 1)
        )
        let isPointerInside = collapsedInteractiveRect(for: viewModel, on: screen).contains(normalizedMouseLocation)
        window.ignoresMouseEvents = !isPointerInside

        if isPointerInside {
            NSCursor.arrow.set()
        }

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

    private func targetWindowAndViewModelForShortcut() -> (window: NSWindow?, viewModel: NotcheraViewModel) {
        let mouseLocation = NSEvent.mouseLocation
        var targetWindow = window
        var viewModel = vm

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                if let uuid = screen.displayUUID {
                    if let screenWindow = windows[uuid] {
                        targetWindow = screenWindow
                    }

                    if let screenViewModel = viewModels[uuid] {
                        viewModel = screenViewModel
                    }
                    break
                }
            }
        }

        return (targetWindow, viewModel)
    }

    private func startKeyboardDismissClickMonitoring(for window: NSWindow, viewModel: NotcheraViewModel) {
        stopKeyboardDismissClickMonitoring()

        keyboardDismissClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak window, weak viewModel] _ in
            Task { @MainActor in
                guard let self, let window, let viewModel else { return }
                guard self.coordinator.notchKeyboardDismissActive else { return }

                let clickLocation = NSEvent.mouseLocation
                if !window.frame.contains(clickLocation) {
                    self.endClipboardKeyboardFocus(shouldCloseNotch: false)
                    viewModel.close()
                }
            }
        }
    }

    private func stopKeyboardDismissClickMonitoring() {
        if let keyboardDismissClickMonitor {
            NSEvent.removeMonitor(keyboardDismissClickMonitor)
            self.keyboardDismissClickMonitor = nil
        }
    }

    private func beginClipboardKeyboardFocus(on window: NSWindow?, viewModel: NotcheraViewModel) {
        clipboardFocusedViewModel = viewModel
        guard let panel = window as? NotcheraSkyLightWindow else { return }
        panel.setClipboardKeyboardFocusEnabled(false)
        NotchKeyboardInterceptor.shared.start(mode: keyboardSessionMode(for: coordinator.currentView))
        startKeyboardDismissClickMonitoring(for: panel, viewModel: viewModel)
    }

    private func endClipboardKeyboardFocus(shouldCloseNotch: Bool = false) {
        coordinator.clipboardKeyboardNavigationActive = false
        coordinator.notchKeyboardDismissActive = false
        NotchKeyboardInterceptor.shared.stop()
        stopKeyboardDismissClickMonitoring()

        let allWindows = [window] + Array(windows.values)
        for currentWindow in allWindows {
            guard let panel = currentWindow as? NotcheraSkyLightWindow else { continue }
            panel.setClipboardKeyboardFocusEnabled(false)
        }

        if shouldCloseNotch {
            clipboardFocusedViewModel?.close()
        }

        clipboardFocusedViewModel = nil
    }

    private func keyboardSessionMode(for view: NotchViews) -> NotchKeyboardInterceptor.Mode {
        switch view {
        case .commandPalette:
            .commandPalette
        case .clipboard:
            .clipboard
        default:
            .dismissOnly
        }
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.notchShelf] else { return }

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
        let windowSize = notchWindowSize(on: screen)
        let notchHeight = max(72, windowSize.height / 2)
        let notchWidth = max(220, windowSize.width / 2)

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
            viewModel.open(forceView: .shelf)
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open(forceView: .shelf)
        }
    }

    private func createNotcheraWindow(for screen: NSScreen, with viewModel: NotcheraViewModel) -> NSWindow {
        let rect = notchWindowFrame(on: screen)
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

        window.setFrame(notchWindowFrame(on: screen), display: true)
    }

    private func createLockScreenMediaWindow(for screen: NSScreen) -> NSWindow {
        let size = CGSize(width: 330, height: 144)
        let window = NotcheraSkyLightWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: LockScreenMediaOverlayView())
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.enableSkyLight()
        positionLockScreenMediaWindow(window, on: screen)
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return window
    }

    private func positionLockScreenMediaWindow(_ window: NSWindow, on screen: NSScreen) {
        let frame = screen.frame
        let yOffset: CGFloat = 160
        window.setFrameOrigin(
            NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2 - yOffset
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

        let updateScreenRecordingMonitoring = {
            if Defaults[.hudReplacement], Defaults[.enableScreenRecordingDetection] {
                ScreenRecordingManager.shared.startMonitoring()
            } else {
                ScreenRecordingManager.shared.stopMonitoring()
            }
        }

        updateScreenRecordingMonitoring()
        ClipboardHistoryManager.shared.startMonitoring()
        _ = PreventSleepManager.shared

        Defaults.publisher(.enableClipboardHistory)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { isEnabled in
                if isEnabled {
                    ClipboardHistoryManager.shared.startMonitoring()
                    ClipboardHistoryManager.shared.pruneExpiredItems()
                } else {
                    ClipboardHistoryManager.shared.stopMonitoring()
                }
            }
            .store(in: &appCancellables)

        Publishers.CombineLatest(
            Defaults.publisher(.hudReplacement).map(\.newValue).removeDuplicates(),
            Defaults.publisher(.enableScreenRecordingDetection).map(\.newValue).removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { _, _ in
            updateScreenRecordingMonitoring()
        }
        .store(in: &appCancellables)

        Defaults.publisher(.notchShelf)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupDragDetectors()
            }
            .store(in: &appCancellables)

        coordinator.$currentView
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                syncKeyboardSession()
            }
            .store(in: &appCancellables)

        Defaults.publisher(.showOnLockScreen)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &appCancellables)

        coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &appCancellables)

        Publishers.CombineLatest(
            musicManager.$isPlaying.removeDuplicates(),
            musicManager.$isPlayerIdle.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.updateLockScreenMediaWindowVisibility()
        }
        .store(in: &appCancellables)

        NotificationCenter.default.addObserver(
            forName: .endClipboardKeyboardNavigation,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let shouldCloseNotch = notification.userInfo?["shouldCloseNotch"] as? Bool ?? false
            self?.endClipboardKeyboardFocus(shouldCloseNotch: shouldCloseNotch)
        }

        KeyboardShortcuts.onKeyDown(for: .commandPalette) { [weak self] in
            Task { [weak self] in
                guard let self,
                      !(self.isScreenLocked && Defaults[.showOnLockScreen]),
                      Defaults[.enableCommandLauncher]
                else { return }
                let target = targetWindowAndViewModelForShortcut()

                await MainActor.run {
                    if target.viewModel.notchState == .open,
                       self.coordinator.currentView == .commandPalette,
                       self.coordinator.commandPaletteModule == .appLauncher
                    {
                        self.closeNotchTask?.cancel()
                        self.closeNotchTask = nil
                        target.viewModel.close()
                        self.endClipboardKeyboardFocus()
                        return
                    }

                    self.closeNotchTask?.cancel()
                    self.closeNotchTask = nil
                    self.coordinator.clipboardKeyboardNavigationActive = true
                    self.coordinator.notchKeyboardDismissActive = true
                    self.coordinator.prepareCommandPalette(module: .appLauncher, rememberView: false)
                    target.viewModel.open(forceView: .commandPalette, rememberForcedView: false)
                    self.beginClipboardKeyboardFocus(on: target.window, viewModel: target.viewModel)
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel) { [weak self] in
            Task { [weak self] in
                guard let self,
                      !(self.isScreenLocked && Defaults[.showOnLockScreen]),
                      Defaults[.enableClipboardHistory]
                else { return }
                let target = targetWindowAndViewModelForShortcut()

                await MainActor.run {
                    if target.viewModel.notchState == .open,
                       self.coordinator.currentView == .clipboard
                    {
                        self.closeNotchTask?.cancel()
                        self.closeNotchTask = nil
                        target.viewModel.close()
                        self.endClipboardKeyboardFocus()
                        return
                    }

                    self.closeNotchTask?.cancel()
                    self.closeNotchTask = nil
                    self.coordinator.clipboardKeyboardNavigationActive = true
                    self.coordinator.notchKeyboardDismissActive = true
                    self.coordinator.clipboardSearchQuery = ""
                    target.viewModel.open(forceView: .clipboard, rememberForcedView: false)
                    self.beginClipboardKeyboardFocus(on: target.window, viewModel: target.viewModel)
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self, !(self.isScreenLocked && Defaults[.showOnLockScreen]) else { return }

                let target = targetWindowAndViewModelForShortcut()
                let viewModel = target.viewModel

                closeNotchTask?.cancel()
                closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        self.coordinator.notchKeyboardDismissActive = true
                        viewModel.open()
                        self.beginClipboardKeyboardFocus(on: target.window, viewModel: viewModel)
                    }

                    let task = Task { [weak self, weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                                self?.endClipboardKeyboardFocus()
                            }
                        } catch {}
                    }
                    closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                        self.endClipboardKeyboardFocus()
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
        timer = Timer.scheduledTimer(withTimeInterval: windowInteractivityPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowInteractivity()
            }
        }
        timer?.tolerance = windowInteractivityPollingInterval / 2
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        setupCursorMonitoring()
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

        updateLockScreenMediaWindowVisibility()
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

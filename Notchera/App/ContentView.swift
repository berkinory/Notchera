import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverOpenTask: Task<Void, Never>?
    @State private var closeTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var hoverPreviewActive: Bool = false
    @State private var preOpenTask: Task<Void, Never>?
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var suppressAutoCloseUntil: Date = .distantPast
    @State private var postOpenHoverValidationTask: Task<Void, Never>?

    @Namespace var albumArtNamespace

    private let hoverAnimation = Animation.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0)
    private let notchOpenAnimation = Animation.spring(response: 0.35, dampingFraction: 0.76, blendDuration: 0)
    private let notchCloseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0)
    private let liveActivityAnimation = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)

    private var isLockScreenInteractionDisabled: Bool {
        coordinator.isScreenLocked && Defaults[.showOnLockScreen]
    }

    private var allowsLockScreenHUD: Bool {
        !coordinator.isScreenLocked || (Defaults[.showOnLockScreen] && Defaults[.showHUDOnLockScreen])
    }

    private var usesExpandedShell: Bool {
        vm.notchState == .open
    }

    private var topCornerRadius: CGFloat {
        usesExpandedShell
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: usesExpandedShell
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var shellHeight: CGFloat? {
        usesExpandedShell ? vm.notchSize.height : nil
    }

    private var currentWindowSize: CGSize {
        guard let screen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID) ?? NSScreen.main else {
            return windowSize
        }

        return notchWindowSize(on: screen)
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
           vm.notchState == .closed, Defaults[.hudReplacement], Defaults[.showPowerStatusNotifications], allowsLockScreenHUD
        {
            chinWidth = openNotchSize.width
        } else if !coordinator.expandingView.show,
                  vm.notchState == .closed,
                  musicManager.isPlaying || !musicManager.isPlayerIdle,
                  coordinator.musicLiveActivityEnabled, !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    private var closedNotchHoverEffectActive: Bool {
        vm.notchState == .closed && hoverPreviewActive && !coordinator.hud.show
    }

    private var availableTabs: [TabModel] {
        tabs
    }

    private var trackpadTabSwitchEnabled: Bool {
        vm.notchState == .open && Defaults[.trackpadTabSwitch] && availableTabs.count > 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        usesExpandedShell
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], usesExpandedShell ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(.black)
                                .frame(height: 1)
                                .padding(.horizontal, topCornerRadius)
                                .allowsHitTesting(false)

                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .frame(height: 12)
                                .allowsHitTesting(vm.notchState == .closed && !isLockScreenInteractionDisabled)
                                .onTapGesture {
                                    guard !isLockScreenInteractionDisabled else { return }
                                    beginTapOpen()
                                }
                        }
                    }
                    .scaleEffect(closedNotchHoverEffectActive ? 1.032 : 1, anchor: .top)
                    .shadow(
                        color: closedNotchHoverEffectActive
                            ? .black.opacity(0.82)
                            : usesExpandedShell
                            ? .black.opacity(0.5)
                            : isHovering
                            ? .black.opacity(0.42)
                            : .black.opacity(0.3),
                        radius: closedNotchHoverEffectActive ? 24 : (usesExpandedShell ? 14 : 12),
                        y: closedNotchHoverEffectActive ? 6 : (usesExpandedShell ? 4 : 3)
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )

                mainLayout
                    .frame(height: shellHeight)
                    .conditionalModifier(true) { view in
                        let shellAnimation = vm.notchState == .open
                            ? notchOpenAnimation
                            : notchCloseAnimation

                        return view
                            .animation(shellAnimation, value: vm.notchState)
                            .animation(hoverAnimation, value: closedNotchHoverEffectActive)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        guard !isLockScreenInteractionDisabled else { return }
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        guard !isLockScreenInteractionDisabled, vm.notchState == .closed else { return }
                        beginTapOpen()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open, !isHovering, !vm.isBatteryPopoverActive {
                            scheduleClose(after: .milliseconds(100))
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed, isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive, !isHovering, vm.notchState == .open, !SharingStateManager.shared.preventNotchClose {
                            scheduleClose(after: .milliseconds(100))
                        }
                    }
                    .contextMenu {
                        if !isLockScreenInteractionDisabled {
                            Button {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    }

                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: currentWindowSize.width, maxHeight: currentWindowSize.height, alignment: .top)
        .animation(liveActivityAnimation, value: musicManager.isPlaying || !musicManager.isPlayerIdle)
        .background(dragDetector)
        .forceArrowCursor()
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .overlay {
            TrackpadTabSwitchRegion(
                isEnabled: trackpadTabSwitchEnabled,
                shouldHandle: isPointerWithinExpandedNotchBounds,
                onHorizontalSwipe: handleTrackpadTabSwitch
            )
        }
        .background {
            NotchEscapeKeyHandler(
                isEnabled: vm.notchState == .open && coordinator.notchKeyboardDismissActive,
                onEscape: handleKeyboardEscape
            )
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                guard Defaults[.notchShelf] else { return }

                coordinator.showShelf()

                if vm.notchState == .closed {
                    beginTapOpen(forceView: .shelf)
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                let closedHUDVisible = coordinator.hud.show && coordinator.hud.type != .battery && vm.notchState == .closed && allowsLockScreenHUD

                if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
                   vm.notchState == .closed, Defaults[.hudReplacement], Defaults[.showPowerStatusNotifications], allowsLockScreenHUD
                {
                        WingHUDView(
                            type: .constant(.battery),
                            value: .constant(CGFloat(batteryModel.levelBattery / 100)),
                            icon: .constant(""),
                            label: .constant(""),
                            duration: .constant(1.5),
                            custom: .constant(nil),
                            showsPercentage: true,
                            isOpen: false,
                            batteryStatusText: batteryModel.statusText,
                            batteryIsCharging: batteryModel.isCharging,
                            batteryIsPluggedIn: batteryModel.isPluggedIn,
                            batteryIsInLowPowerMode: batteryModel.isInLowPowerMode
                        )
                        .fixedSize()
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                    } else if vm.notchState == .closed {
                        if closedHUDVisible {
                            WingHUDView(
                                type: $coordinator.hud.type,
                                value: $coordinator.hud.value,
                                icon: $coordinator.hud.icon,
                                label: $coordinator.hud.label,
                                duration: $coordinator.hud.duration,
                                custom: $coordinator.hud.custom,
                                showsPercentage: false,
                                isOpen: false,
                                batteryStatusText: nil,
                                batteryIsCharging: false,
                                batteryIsPluggedIn: false,
                                batteryIsInLowPowerMode: false
                            )
                            .fixedSize()
                            .transition(.opacity)
                        } else if !coordinator.expandingView.show,
                                  musicManager.isPlaying || !musicManager.isPlayerIdle,
                                  coordinator.musicLiveActivityEnabled,
                                  !vm.hideOnClosed
                        {
                            CompactActivityHost(hoverBoostActive: closedNotchHoverEffectActive)
                                .frame(alignment: .center)
                        } else {
                            Rectangle()
                                .fill(.clear)
                                .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                        }
                    } else if vm.notchState == .open {
                        if coordinator.hud.show, coordinator.hud.type != .battery {
                            WingHUDView(
                                type: $coordinator.hud.type,
                                value: $coordinator.hud.value,
                                icon: $coordinator.hud.icon,
                                label: $coordinator.hud.label,
                                duration: $coordinator.hud.duration,
                                custom: $coordinator.hud.custom,
                                showsPercentage: false,
                                isOpen: true,
                                batteryStatusText: nil,
                                batteryIsCharging: false,
                                batteryIsPluggedIn: false,
                                batteryIsInLowPowerMode: false
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(24, vm.effectiveClosedNotchHeight))
                            .transition(.opacity)
                        } else {
                            NotcheraHeader()
                                .frame(height: max(24, vm.effectiveClosedNotchHeight))
                        }
                    } else {
                        Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                    }
            }
            .zIndex(2)
            if vm.notchState == .open {
                ZStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                            .transition(.opacity)
                    case .calendar:
                        CalendarTabView()
                            .transition(.opacity)
                    case .clipboard:
                        ClipboardTabView()
                            .transition(.opacity)
                    case .shelf:
                        ShelfView()
                            .transition(.opacity)
                    case .aiUsage:
                        AIUsageDashboardView()
                            .transition(.opacity)
                    case .commandPalette:
                        CommandPaletteView()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(coordinator.currentView)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.22, dampingFraction: 0.82, blendDuration: 0).delay(0.02)),
                        removal: .scale(scale: 0.98, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.easeOut(duration: 0.08))
                    )
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
            }
        }
        .onDrop(of: [.fileURL], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func CompactActivityHost(hoverBoostActive: Bool) -> some View {
        if musicManager.isPlaying || !musicManager.isPlayerIdle {
            MusicCompactActivityView(
                albumArtNamespace: albumArtNamespace,
                hoverBoostActive: hoverBoostActive
            )
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.notchShelf], vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $vm.dragDetectorTargeting) { providers in
                    vm.dropEvent = true
                    ShelfStateViewModel.shared.load(providers)
                    return true
                }
        }
    }

    private func beginTapOpen(forceView: NotchViews? = nil) {
        guard vm.notchState == .closed else { return }

        hoverOpenTask?.cancel()
        closeTask?.cancel()
        preOpenTask?.cancel()

        withAnimation(hoverAnimation) {
            hoverPreviewActive = true
        }

        preOpenTask = Task {
            try? await Task.sleep(for: .milliseconds(72))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                doOpen(forceView: forceView)
            }
        }
    }

    private func doOpen(forceView: NotchViews? = nil) {
        suppressAutoCloseUntil = Date().addingTimeInterval(0.2)
        hoverOpenTask?.cancel()
        closeTask?.cancel()
        preOpenTask?.cancel()
        postOpenHoverValidationTask?.cancel()

        withAnimation(notchOpenAnimation) {
            vm.open(forceView: forceView)
        }

        postOpenHoverValidationTask = Task {
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard vm.notchState == .open else { return }

                let pointerInsideTopRegion = isPointerWithinTopNotchRegion()
                if pointerInsideTopRegion {
                    isHovering = true
                    return
                }

                withAnimation(hoverAnimation) {
                    isHovering = false
                    hoverPreviewActive = false
                }

                if !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose {
                    closeIfPossible()
                }
            }
        }
    }

    private func isPointerWithinTopNotchRegion() -> Bool {
        guard let screenFrame = getScreenFrame(coordinator.selectedScreenUUID) else { return false }

        let mouse = NSEvent.mouseLocation
        let normalizedPoint = CGPoint(
            x: mouse.x,
            y: min(mouse.y, screenFrame.maxY - 1)
        )

        let width = currentWindowSize.width
        let height = currentWindowSize.height + 12
        let region = CGRect(
            x: screenFrame.midX - (width / 2),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )

        return region.contains(normalizedPoint)
    }

    private func isPointerWithinExpandedNotchBounds() -> Bool {
        guard vm.notchState == .open,
              let screenFrame = getScreenFrame(coordinator.selectedScreenUUID)
        else {
            return false
        }

        let mouse = NSEvent.mouseLocation
        let normalizedPoint = CGPoint(
            x: mouse.x,
            y: min(mouse.y, screenFrame.maxY - 1)
        )

        let region = CGRect(
            x: screenFrame.midX - (currentWindowSize.width / 2),
            y: screenFrame.maxY - currentWindowSize.height,
            width: currentWindowSize.width,
            height: currentWindowSize.height
        )

        return region.contains(normalizedPoint)
    }

    private func handleTrackpadTabSwitch(_ horizontalDelta: CGFloat) {
        guard horizontalDelta != 0,
              availableTabs.count > 1,
              let currentIndex = availableTabs.firstIndex(where: { $0.view == coordinator.currentView })
        else {
            return
        }

        let step = horizontalDelta > 0 ? -1 : 1
        let nextIndex = (currentIndex + step + availableTabs.count) % availableTabs.count

        withAnimation(.smooth) {
            coordinator.currentView = availableTabs[nextIndex].view
        }
    }

    private func handleKeyboardEscape() {
        hoverOpenTask?.cancel()
        closeTask?.cancel()
        preOpenTask?.cancel()
        postOpenHoverValidationTask?.cancel()
        anyDropDebounceTask?.cancel()

        NotificationCenter.default.post(name: .endClipboardKeyboardNavigation, object: nil)

        withAnimation(notchCloseAnimation) {
            isHovering = false
            hoverPreviewActive = false
            vm.close()
        }
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }

        if hovering {
            closeTask?.cancel()
            preOpenTask?.cancel()

            let shouldShowHoverPreview = vm.notchState == .closed
                && !coordinator.hud.show
                && (!Defaults[.openNotchOnHover] || Defaults[.minimumHoverDuration] > 0.01)

            withAnimation(hoverAnimation) {
                isHovering = true
                hoverPreviewActive = shouldShowHoverPreview
            }

            guard vm.notchState == .closed,
                  !coordinator.hud.show,
                  Defaults[.openNotchOnHover] else { return }

            hoverOpenTask?.cancel()
            hoverOpenTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard vm.notchState == .closed,
                          isHovering,
                          !coordinator.hud.show else { return }

                    doOpen()
                }
            }
        } else {
            hoverOpenTask?.cancel()
            preOpenTask?.cancel()

            withAnimation(hoverAnimation) {
                isHovering = false
                hoverPreviewActive = false
            }

            scheduleClose(after: .milliseconds(40))
        }
    }

    private func scheduleClose(after delay: Duration) {
        closeTask?.cancel()
        closeTask = Task {
            try? await Task.sleep(for: delay)

            let remainingSuppressDuration = suppressAutoCloseUntil.timeIntervalSinceNow
            if remainingSuppressDuration > 0 {
                try? await Task.sleep(for: .seconds(remainingSuppressDuration))
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                closeIfPossible()
            }
        }
    }

    private func closeIfPossible() {
        guard vm.notchState == .open,
              !isHovering,
              !vm.isBatteryPopoverActive,
              !SharingStateManager.shared.preventNotchClose
        else {
            return
        }

        vm.close()
    }
}

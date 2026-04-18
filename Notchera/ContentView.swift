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
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var suppressAutoCloseUntil: Date = .distantPast
    @State private var postOpenHoverValidationTask: Task<Void, Never>?

    @Namespace var albumArtNamespace

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let liveActivityAnimation = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)

    private var topCornerRadius: CGFloat {
        vm.notchState == .open
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: vm.notchState == .open
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
           vm.notchState == .closed, Defaults[.showPowerStatusNotifications]
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
        guard vm.notchState == .closed,
              isHovering,
              !coordinator.hud.show else { return false }

        if !Defaults[.openNotchOnHover] {
            return true
        }

        return Defaults[.minimumHoverDuration] > 0.01
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
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
                                .allowsHitTesting(vm.notchState == .closed)
                                .onTapGesture {
                                    doOpen()
                                }
                        }
                    }
                    .scaleEffect(closedNotchHoverEffectActive ? 1.020 : 1, anchor: .top)
                    .shadow(
                        color: closedNotchHoverEffectActive
                            ? .black.opacity(0.72)
                            : (vm.notchState == .open || isHovering)
                                ? .black.opacity(0.4)
                                : .clear,
                        radius: closedNotchHoverEffectActive ? 16 : 1,
                        y: closedNotchHoverEffectActive ? 4 : 0
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )

                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        let shellAnimation = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0)

                        return view
                            .animation(shellAnimation, value: vm.notchState)
                            .animation(.easeOut(duration: 0.18), value: closedNotchHoverEffectActive)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        guard vm.notchState == .closed else { return }
                        doOpen()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open, !isHovering, !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    guard Date() >= suppressAutoCloseUntil else { return }
                                    if vm.notchState == .open, !isHovering, !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose {
                                        vm.close()
                                    }
                                }
                            }
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
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    guard Date() >= suppressAutoCloseUntil else { return }
                                    if !vm.isBatteryPopoverActive, !isHovering, vm.notchState == .open, !SharingStateManager.shared.preventNotchClose {
                                        vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }

                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .animation(liveActivityAnimation, value: musicManager.isPlaying || !musicManager.isPlayerIdle)
        .background(dragDetector)
        .forceArrowCursor()
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                guard Defaults[.notchShelf] else { return }

                coordinator.showShelf()

                if vm.notchState == .closed {
                    doOpen(forceView: .shelf)
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
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    let closedHUDVisible = coordinator.hud.show && coordinator.hud.type != .battery && vm.notchState == .closed

                    if coordinator.expandingView.type == .battery, coordinator.expandingView.show,
                       vm.notchState == .closed, Defaults[.showPowerStatusNotifications]
                    {
                        WingHUDView(
                            type: .constant(.battery),
                            value: .constant(CGFloat(batteryModel.levelBattery / 100)),
                            icon: .constant(""),
                            label: .constant(""),
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
                        let closedContentOpacity: Double = vm.notchState == .open ? 0 : 1

                        ZStack {
                            if !coordinator.expandingView.show,
                               musicManager.isPlaying || !musicManager.isPlayerIdle,
                               coordinator.musicLiveActivityEnabled,
                               !vm.hideOnClosed
                            {
                                CompactActivityHost()
                                    .frame(alignment: .center)
                                    .opacity(closedHUDVisible ? 0.0 : closedContentOpacity)
                                    .animation(.easeIn(duration: 0.08), value: vm.notchState)
                            } else {
                                Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                                    .opacity(closedHUDVisible ? 0.0 : closedContentOpacity)
                                    .animation(.easeIn(duration: 0.08), value: vm.notchState)
                            }

                            if closedHUDVisible {
                                WingHUDView(
                                    type: $coordinator.hud.type,
                                    value: $coordinator.hud.value,
                                    icon: $coordinator.hud.icon,
                                    label: $coordinator.hud.label,
                                    showsPercentage: false,
                                    isOpen: false,
                                    batteryStatusText: nil,
                                    batteryIsCharging: false,
                                    batteryIsPluggedIn: false,
                                    batteryIsInLowPowerMode: false
                                )
                                .fixedSize()
                                .transition(.opacity)
                            }
                        }
                    } else if vm.notchState == .open {
                        if coordinator.hud.show, coordinator.hud.type != .battery, Defaults[.showOpenNotchHUD] {
                            WingHUDView(
                                type: $coordinator.hud.type,
                                value: $coordinator.hud.value,
                                icon: $coordinator.hud.icon,
                                label: $coordinator.hud.label,
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
            }
            .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0).delay(0.03)),
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
    func CompactActivityHost() -> some View {
        if musicManager.isPlaying || !musicManager.isPlayerIdle {
            MusicCompactActivityView(albumArtNamespace: albumArtNamespace)
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

    private func doOpen(forceView: NotchViews? = nil) {
        suppressAutoCloseUntil = Date().addingTimeInterval(0.5)
        postOpenHoverValidationTask?.cancel()

        withAnimation(animationSpring) {
            vm.open(forceView: forceView)
        }

        postOpenHoverValidationTask = Task {
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard vm.notchState == .open else { return }
                guard !isPointerWithinTopNotchRegion() else { return }

                withAnimation(animationSpring) {
                    isHovering = false
                }

                if !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose {
                    vm.close()
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

        let width = openNotchSize.width + 36
        let height = openNotchSize.height + 32
        let region = CGRect(
            x: screenFrame.midX - (width / 2),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )

        return region.contains(normalizedPoint)
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            guard vm.notchState == .closed,
                  !coordinator.hud.show,
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
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
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        isHovering = false
                    }

                    guard Date() >= suppressAutoCloseUntil else { return }

                    if vm.notchState == .open, !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose {
                        vm.close()
                    }
                }
            }
        }
    }
}

struct MusicCompactActivityView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        style: .continuous
                    )
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 10),
                    height: max(0, vm.effectiveClosedNotchHeight - 10)
                )

            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width
                        + -cornerRadiusInsets.closed.top
                )

            MusicSpectrumIndicatorView(
                albumArtNamespace: albumArtNamespace,
                isPlaying: musicManager.isPlaying,
                avgColor: musicManager.avgColor,
                barWidth: 50,
                spectrumSize: CGSize(width: 16, height: 12),
                containerSize: CGSize(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                ),
                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }

    func performDrop(info _: DropInfo) -> Bool {
        false
    }
}

#Preview {
    let vm = NotcheraViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}

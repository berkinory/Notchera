import AVFoundation
import Defaults
import SwiftUI

private final class BluetoothLoopingPlayerController {
    private let playbackRate: Float = 1.25

    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.playImmediately(atRate: playbackRate)
    }

    deinit {
        player.pause()
        looper = nil
    }
}

private struct BluetoothLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)

        context.coordinator.attach(playerLayer: playerLayer, url: url)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var controller: BluetoothLoopingPlayerController?

        func attach(playerLayer: AVPlayerLayer, url: URL) {
            controller = BluetoothLoopingPlayerController(url: url)
            playerLayer.player = controller?.player
        }
    }
}

struct WingHUDView: View {
    private static let displayValues = (0 ... 100).map(String.init)

    @EnvironmentObject var vm: NotcheraViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var label: String
    @Binding var duration: TimeInterval
    @Binding var custom: ExternalHUDRequest?
    @Default(.animateBluetoothAudioIndicator) var animateBluetoothAudioIndicator
    @Default(.showSystemValueInHUD) var showSystemValueInHUD
    let showsPercentage: Bool
    let isOpen: Bool
    let batteryStatusText: String?
    let batteryIsCharging: Bool
    let batteryIsPluggedIn: Bool
    let batteryIsInLowPowerMode: Bool

    private var notchHeight: CGFloat {
        guard let screen = vm.screenUUID.flatMap(NSScreen.screen(withUUID:)) else {
            return max(24, vm.effectiveClosedNotchHeight)
        }

        return snapToDevicePixels(max(24, vm.effectiveClosedNotchHeight), on: screen)
    }

    private var centerWidth: CGFloat {
        guard let screen = vm.screenUUID.flatMap(NSScreen.screen(withUUID:)) else {
            return max(0, vm.closedNotchSize.width - 20)
        }

        return snapToDevicePixels(max(0, vm.closedNotchSize.width - 20), on: screen)
    }

    private var usesFlexibleCenterWidth: Bool {
        isOpen
    }

    private var wingWidth: CGFloat {
        let scale: CGFloat = 1.0
        return 106 * scale
    }

    private var titleWidth: CGFloat {
        max(0, wingWidth - 18 - 5 - 12)
    }

    private var marqueeDelay: Double {
        max(0, duration / 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth, height: notchHeight, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(maxWidth: usesFlexibleCenterWidth ? .infinity : centerWidth, maxHeight: notchHeight)
                .frame(width: usesFlexibleCenterWidth ? nil : centerWidth, height: notchHeight)

            rightWing
                .frame(width: wingWidth, height: notchHeight, alignment: .trailing)
        }
        .frame(
            maxWidth: usesFlexibleCenterWidth ? .infinity : wingWidth + centerWidth + wingWidth,
            maxHeight: notchHeight,
            alignment: .center
        )
        .frame(
            width: usesFlexibleCenterWidth ? nil : wingWidth + centerWidth + wingWidth,
            height: notchHeight,
            alignment: .center
        )
        .symbolVariant(.fill)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(isOpen ? 0.42 : 0.32), radius: isOpen ? 12 : 10, y: isOpen ? 4 : 3)
        .animation(.smooth(duration: 0.18), value: type)
        .animation(.smooth(duration: 0.18), value: isOpen)
    }

    @ViewBuilder
    private var leftWing: some View {
        if type == .custom, let custom {
            HStack(spacing: 5) {
                ForEach(Array(custom.left.enumerated()), id: \.offset) { entry in
                    customItemView(entry.element, side: .left)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .padding(.leading, 6)
            .padding(.trailing, 6)
        } else {
            HStack(spacing: 5) {
                ZStack {
                    hudIcon
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .id(hudIconKey)
                }
                .frame(width: 18, height: 18)
                .animation(.smooth(duration: 0.14), value: hudIconKey)

                MarqueeText(
                    .constant(title),
                    font: .footnote.weight(.medium),
                    nsFont: .subheadline,
                    textColor: .white,
                    backgroundColor: .clear,
                    minDuration: marqueeDelay,
                    frameWidth: titleWidth
                )
                .frame(width: titleWidth, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if type == .custom, let custom {
            HStack(spacing: 6) {
                ForEach(Array(custom.right.enumerated()), id: \.offset) { entry in
                    customItemView(entry.element, side: .right)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .clipped()
            .padding(.leading, 6)
            .padding(.trailing, 6)
        } else if type == .battery {
            HStack(spacing: 6) {
                BatteryView(
                    levelBattery: Float(clampedValue * 100),
                    isPluggedIn: batteryIsPluggedIn,
                    isCharging: batteryIsCharging,
                    isInLowPowerMode: batteryIsInLowPowerMode,
                    batteryWidth: 30,
                    isForNotification: true
                )
                .scaleEffect(0.78)
                .frame(width: 20, height: 14)

                Text("%\(displayValue)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
        } else if type == .recording ||
            type == .capsLock ||
            type == .inputSource ||
            type == .focus ||
            type == .bluetoothAudio ||
            type == .hudEnabled
        {
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: statusWidth, alignment: .trailing)
                .padding(.trailing, 6)
        } else {
            HStack(spacing: showSystemValueInHUD ? 3 : 0) {
                DraggableProgressBar(value: $value, onChange: setSystemValue)

                if showSystemValueInHUD {
                    ZStack {
                        Text(displayValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .monospacedDigit()
                            .id(displayValue)
                            .transition(.asymmetric(
                                insertion: .offset(y: 2).combined(with: .opacity),
                                removal: .offset(y: -2).combined(with: .opacity)
                            ))
                    }
                    .frame(width: 24, height: 14, alignment: .trailing)
                    .clipped()
                    .animation(.easeOut(duration: 0.12), value: displayValue)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private var hudIcon: some View {
        switch type {
        case .volume:
            if icon.isEmpty {
                Image(systemName: speakerSymbol)
                    .symbolVariant(clampedValue > 0 ? .none : .slash)
            } else {
                Image(systemName: icon)
                    .opacity(clampedValue.isZero ? 0.6 : 1)
                    .scaleEffect(clampedValue.isZero ? 0.85 : 1)
            }
        case .brightness:
            Image(systemName: brightnessSymbol)
        case .backlight:
            Image(systemName: clampedValue > 0.5 ? "light.max" : "light.min")
        case .capsLock:
            Image(systemName: clampedValue > 0 ? "capslock.fill" : "capslock")
        case .inputSource:
            Image(systemName: icon.isEmpty ? "translate" : icon)
        case .focus:
            Image(systemName: icon.isEmpty ? "moon.fill" : icon)
        case .bluetoothAudio:
            if let bluetoothAnimationURL {
                BluetoothLoopingVideoIcon(url: bluetoothAnimationURL, size: CGSize(width: 18, height: 18))
            } else {
                Image(systemName: icon.isEmpty ? "bluetooth" : icon)
            }
        case .recording:
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
        case .battery:
            Image(systemName: batteryMonoSymbol)
                .foregroundStyle(.white)
        case .hudEnabled:
            Image(systemName: "switch.2")
                .foregroundStyle(.green)
        default:
            EmptyView()
        }
    }

    private var title: String {
        switch type {
        case .volume:
            "Volume"
        case .brightness:
            "Brightness"
        case .backlight:
            "Backlight"
        case .capsLock:
            "Caps Lock"
        case .inputSource:
            "Input Changed"
        case .focus:
            label.isEmpty ? "Focus" : label
        case .bluetoothAudio:
            label.isEmpty ? "Bluetooth Audio" : label
        case .recording:
            "Recording"
        case .battery:
            batteryStatusText ?? "Battery"
        case .hudEnabled:
            "HUD Enabled"
        default:
            ""
        }
    }

    private var displayValue: String {
        let index = Int((clampedValue * 100).rounded())
        return Self.displayValues[index]
    }

    private var statusText: String {
        switch type {
        case .capsLock:
            clampedValue > 0 ? "On" : "Off"
        case .inputSource:
            label.isEmpty ? "--" : label
        case .focus:
            clampedValue > 0 ? "Enabled" : "Disabled"
        case .bluetoothAudio:
            "Connected"
        case .recording:
            label.isEmpty ? "00:00" : label
        case .hudEnabled:
            "On"
        default:
            displayValue
        }
    }

    private var statusWidth: CGFloat {
        switch type {
        case .recording:
            44
        case .inputSource:
            36
        case .focus:
            48
        case .bluetoothAudio:
            60
        case .capsLock:
            24
        case .hudEnabled:
            24
        default:
            24
        }
    }

    private var statusColor: Color {
        switch type {
        case .capsLock:
            clampedValue > 0 ? .green : .gray
        case .inputSource:
            .white
        case .focus:
            clampedValue > 0 ? .indigo : .gray
        case .bluetoothAudio:
            .green
        case .hudEnabled:
            .green
        default:
            .gray
        }
    }

    private var bluetoothAnimationURL: URL? {
        guard type == .bluetoothAudio,
              animateBluetoothAudioIndicator,
              let assetBaseName = bluetoothAnimationAssetBaseName
        else {
            return nil
        }

        return Bundle.main.url(
            forResource: assetBaseName,
            withExtension: "mov",
            subdirectory: "BluetoothHUDAnimations"
        ) ?? Bundle.main.url(forResource: assetBaseName, withExtension: "mov")
    }

    private var bluetoothAnimationAssetBaseName: String? {
        switch icon {
        case "airpods":
            "airpods"
        case "airpods.gen3":
            "airpodsGen3"
        case "airpods.gen4":
            "airpodsGen4"
        case "airpods.pro":
            "airpodsPro"
        case "airpods.max":
            "airpodsMax"
        default:
            nil
        }
    }

    private var hudIconKey: String {
        switch type {
        case .volume:
            icon.isEmpty
                ? "volume:\(speakerSymbol):\(clampedValue > 0 ? 1 : 0)"
                : "volume-custom:\(icon):\(clampedValue > 0 ? 1 : 0)"
        case .brightness:
            "brightness:\(brightnessSymbol)"
        case .backlight:
            clampedValue > 0.5 ? "backlight:max" : "backlight:min"
        case .capsLock:
            clampedValue > 0 ? "capslock:on" : "capslock:off"
        case .inputSource:
            "input-source:\(icon):\(label)"
        case .focus:
            "focus:\(icon):\(label):\(clampedValue > 0 ? 1 : 0)"
        case .bluetoothAudio:
            "bluetooth-audio:\(icon):\(label)"
        case .recording:
            clampedValue > 0 ? "recording:on" : "recording:off"
        case .battery:
            "battery:\(batteryLevelBucket):\(batteryIsPowerConnected ? 1 : 0):\(batteryIsInLowPowerMode ? 1 : 0):\(batteryStatusText ?? "")"
        case .hudEnabled:
            "hud-enabled"
        default:
            ""
        }
    }

    private enum CustomHUDSide {
        case left
        case right
    }

    @ViewBuilder
    private func customItemView(_ item: ExternalHUDItem, side: CustomHUDSide) -> some View {
        switch item.type {
        case .icon:
            Image(systemName: item.symbol ?? "questionmark")
                .foregroundStyle(item.color?.swiftUIColor ?? .white)
                .frame(width: 18, height: 18)
                .id(item.animationKey)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        case .text:
            if side == .left {
                MarqueeText(
                    .constant(item.text ?? ""),
                    font: .footnote.weight(.medium),
                    nsFont: .subheadline,
                    textColor: item.color?.swiftUIColor ?? .white,
                    backgroundColor: .clear,
                    minDuration: marqueeDelay,
                    frameWidth: titleWidth
                )
                .frame(width: titleWidth, alignment: .leading)
            } else {
                Text(item.text ?? "")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(item.color?.swiftUIColor ?? .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 60, alignment: .trailing)
            }
        case .value:
            Text(formattedValue(for: item.value ?? 0))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(item.color?.swiftUIColor ?? .gray)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .contentTransition(.numericText())
        case .slider:
            CustomHUDSliderBar(
                value: CGFloat(item.value ?? 0),
                color: item.color?.swiftUIColor ?? .white
            )
            .frame(width: 48)
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(item.color?.swiftUIColor ?? .white)
                .scaleEffect(0.55)
                .frame(width: 18, height: 18)
        case .spinner:
            NotcheraSpinner(color: item.color?.swiftUIColor ?? .white, lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }

    private func formattedValue(for value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    private var clampedValue: CGFloat {
        max(0, min(value, 1))
    }

    private var speakerSymbol: String {
        switch clampedValue {
        case 0:
            "speaker"
        case 0 ... 0.3:
            "speaker.wave.1"
        case 0.3 ... 0.8:
            "speaker.wave.2"
        case 0.8 ... 1:
            "speaker.wave.3"
        default:
            "speaker.wave.2"
        }
    }

    private var brightnessSymbol: String {
        switch clampedValue {
        case 0 ... 0.6:
            "sun.min"
        case 0.6 ... 1:
            "sun.max"
        default:
            "sun.min"
        }
    }

    private var batteryIsPowerConnected: Bool {
        batteryIsCharging || batteryIsPluggedIn
    }

    private var batteryMonoSymbol: String {
        "battery.100"
    }

    private var batteryLevelBucket: String {
        switch Float(clampedValue * 100) {
        case ...10:
            "0"
        case ...20:
            "25"
        case ...50:
            "50"
        case ...75:
            "75"
        default:
            "100"
        }
    }

    private func setSystemValue(_ newValue: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newValue))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newValue))
        case .backlight:
            KeyboardBacklightManager.shared.setAbsolute(value: Float(newValue))
        default:
            break
        }
    }
}

struct NotcheraSpinner: View {
    let color: Color
    var lineWidth: CGFloat = 1.8

    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let inset = lineWidth / 2 + 0.75

            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(inset)

                Circle()
                    .trim(from: 0.1, to: 0.6)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(inset)
                    .rotationEffect(Angle.degrees(isAnimating ? 360 : 0))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .drawingGroup()
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.linear(duration: 0.75).repeatForever(autoreverses: false), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

private struct CustomHUDSliderBar: View {
    let value: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)

                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width * max(0, min(value, 1)), geo.size.width)))
                    .animation(.smooth(duration: 0.18), value: value)
            }
        }
        .frame(height: 6)
    }
}

#Preview {
    WingHUDView(
        type: .constant(.brightness),
        value: .constant(0.4),
        icon: .constant(""),
        label: .constant(""),
        duration: .constant(1.5),
        custom: .constant(nil),
        showsPercentage: true,
        isOpen: false,
        batteryStatusText: nil,
        batteryIsCharging: false,
        batteryIsPluggedIn: false,
        batteryIsInLowPowerMode: false
    )
    .padding(.horizontal, 8)
    .background(Color.black)
    .padding()
    .environmentObject(NotcheraViewModel())
}

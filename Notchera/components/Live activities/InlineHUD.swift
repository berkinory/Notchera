import SwiftUI

struct WingHUDView: View {
    private static let displayValues = (0 ... 100).map(String.init)

    @EnvironmentObject var vm: NotcheraViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var label: String
    let showsPercentage: Bool
    let isOpen: Bool
    let batteryStatusText: String?
    let batteryIsCharging: Bool
    let batteryIsPluggedIn: Bool
    let batteryIsInLowPowerMode: Bool

    private var notchHeight: CGFloat {
        max(24, vm.effectiveClosedNotchHeight)
    }

    private var centerWidth: CGFloat {
        max(0, vm.closedNotchSize.width - 20)
    }

    private var usesFlexibleCenterWidth: Bool {
        isOpen
    }

    private var wingWidth: CGFloat {
        let scale: CGFloat = isOpen ? 1.04 : 1.0
        return 108 * scale
    }

    private var titleWidth: CGFloat {
        max(0, wingWidth - 18 - 5 - 12)
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
        .animation(.smooth(duration: 0.18), value: type)
        .animation(.smooth(duration: 0.18), value: isOpen)
    }

    private var leftWing: some View {
        HStack(spacing: 5) {
            ZStack {
                hudIcon
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .id(hudIconKey)
            }
            .frame(width: 18, height: 18)
            .animation(.smooth(duration: 0.14), value: hudIconKey)

            Text(title)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: titleWidth, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var rightWing: some View {
        if type == .battery {
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
        } else if type == .recording || type == .capsLock || type == .inputSource || type == .hudEnabled {
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: statusWidth, alignment: .trailing)
                .padding(.trailing, 6)
        } else {
            HStack(spacing: 3) {
                DraggableProgressBar(value: $value, onChange: setSystemValue)

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
        case .hudEnabled:
            .green
        default:
            .gray
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
        case .recording:
            clampedValue > 0 ? "recording:on" : "recording:off"
        case .battery:
            "battery:\(batteryMonoSymbol):\(displayValue):\(batteryStatusText ?? "")"
        case .hudEnabled:
            "hud-enabled"
        default:
            ""
        }
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

    private var batteryMonoSymbol: String {
        "battery.100"
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

#Preview {
    WingHUDView(
        type: .constant(.brightness),
        value: .constant(0.4),
        icon: .constant(""),
        label: .constant(""),
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

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
        return 110 * scale
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

                Text(displayValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
        } else if type == .mic || type == .recording {
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: type == .recording ? 44 : 28, alignment: .trailing)
                .padding(.trailing, 6)
        } else {
            HStack(spacing: 3) {
                DraggableProgressBar(value: $value, onChange: setSystemValue)

                Text(displayValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
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
        case .mic:
            Image(systemName: "mic")
                .symbolVariant(clampedValue > 0 ? .none : .slash)
        case .recording:
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
        case .battery:
            Image(systemName: batteryMonoSymbol)
                .foregroundStyle(.white)
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
        case .mic:
            "Mic"
        case .recording:
            "Screen Record"
        case .battery:
            batteryStatusText ?? "Battery"
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
        case .mic:
            clampedValue > 0 ? "On" : "Off"
        case .recording:
            label.isEmpty ? "00:00" : label
        default:
            displayValue
        }
    }

    private var hudIconKey: String {
        switch type {
        case .volume:
            return icon.isEmpty
                ? "volume:\(speakerSymbol):\(clampedValue > 0 ? 1 : 0)"
                : "volume-custom:\(icon):\(clampedValue > 0 ? 1 : 0)"
        case .brightness:
            return "brightness:\(brightnessSymbol)"
        case .backlight:
            return clampedValue > 0.5 ? "backlight:max" : "backlight:min"
        case .mic:
            return clampedValue > 0 ? "mic:on" : "mic:off"
        case .recording:
            return clampedValue > 0 ? "recording:on" : "recording:off"
        case .battery:
            return "battery:\(batteryMonoSymbol):\(displayValue):\(batteryStatusText ?? "")"
        default:
            return ""
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

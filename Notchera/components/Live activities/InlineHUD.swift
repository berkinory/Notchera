import SwiftUI

struct WingHUDView: View {
    private static let displayValues = (0 ... 100).map(String.init)

    @EnvironmentObject var vm: NotcheraViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    let showsPercentage: Bool
    let isOpen: Bool

    private var notchHeight: CGFloat {
        max(24, vm.effectiveClosedNotchHeight)
    }

    private var centerWidth: CGFloat {
        max(0, vm.closedNotchSize.width - 20)
    }

    private var wingWidth: CGFloat {
        let scale: CGFloat = isOpen ? 1.04 : 1.0
        return 104 * scale
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth, height: notchHeight, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth, height: notchHeight)

            rightWing
                .frame(width: wingWidth, height: notchHeight, alignment: .trailing)
        }
        .frame(
            width: wingWidth + centerWidth + wingWidth,
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
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var rightWing: some View {
        if type == .mic {
            Text(displayValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.gray)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
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
                    .symbolVariant(value > 0 ? .none : .slash)
            } else {
                Image(systemName: icon)
                    .opacity(value.isZero ? 0.6 : 1)
                    .scaleEffect(value.isZero ? 0.85 : 1)
            }
        case .brightness:
            Image(systemName: brightnessSymbol)
        case .backlight:
            Image(systemName: value > 0.5 ? "light.max" : "light.min")
        case .mic:
            Image(systemName: "mic")
                .symbolVariant(value > 0 ? .none : .slash)
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
        default:
            ""
        }
    }

    private var displayValue: String {
        let index = Int((max(0, min(value, 1)) * 100).rounded())
        return Self.displayValues[index]
    }

    private var hudIconKey: String {
        switch type {
        case .volume:
            return icon.isEmpty
                ? "volume:\(speakerSymbol):\(value > 0 ? 1 : 0)"
                : "volume-custom:\(icon):\(value > 0 ? 1 : 0)"
        case .brightness:
            return "brightness:\(brightnessSymbol)"
        case .backlight:
            return value > 0.5 ? "backlight:max" : "backlight:min"
        case .mic:
            return value > 0 ? "mic:on" : "mic:off"
        default:
            return ""
        }
    }

    private var speakerSymbol: String {
        switch value {
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
        switch value {
        case 0 ... 0.6:
            "sun.min"
        case 0.6 ... 1:
            "sun.max"
        default:
            "sun.min"
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

#Preview {
    WingHUDView(
        type: .constant(.brightness),
        value: .constant(0.4),
        icon: .constant(""),
        showsPercentage: true,
        isOpen: false
    )
    .padding(.horizontal, 8)
    .background(Color.black)
    .padding()
    .environmentObject(NotcheraViewModel())
}

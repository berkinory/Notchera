import SwiftUI

enum HoverButtonTapEffect {
    case none
    case bounce
    case nudgeLeft
    case nudgeRight
    case rotateClockwise
    case rotateCounterClockwise
}

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var backgroundColor: Color = .clear
    var scale: Image.Scale = .medium
    var contentTransition: ContentTransition = .symbolEffect
    var tapEffect: HoverButtonTapEffect = .none
    var action: () -> Void

    @State private var isHovering = false
    @State private var tapTrigger = 0
    @State private var iconOffset: CGSize = .zero
    @State private var iconRotation: Double = 0

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        let cornerRadius = size * 0.28

        Button {
            triggerTapFeedback()
            action()
        } label: {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if isHovering {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .contentTransition(contentTransition)
                        .font(scale == .large ? .largeTitle : .body)
                        .offset(iconOffset)
                        .rotationEffect(.degrees(iconRotation))
                        .conditionalModifier(tapEffect == .bounce) { view in
                            view.symbolEffect(.bounce, value: tapTrigger)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.smooth(duration: 0.18), value: isHovering)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.22)) {
                isHovering = hovering
            }
        }
    }

    private func triggerTapFeedback() {
        tapTrigger += 1

        switch tapEffect {
        case .none, .bounce:
            return
        case .nudgeLeft:
            animateDirectionalNudge(x: -6)
        case .nudgeRight:
            animateDirectionalNudge(x: 6)
        case .rotateClockwise:
            animateIcon(offset: .zero, rotation: 14)
        case .rotateCounterClockwise:
            animateIcon(offset: .zero, rotation: -14)
        }
    }

    private func animateIcon(offset: CGSize, rotation: Double) {
        withAnimation(.smooth(duration: 0.09)) {
            iconOffset = offset
            iconRotation = rotation
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(95))

            withAnimation(.smooth(duration: 0.18)) {
                iconOffset = .zero
                iconRotation = 0
            }
        }
    }

    private func animateDirectionalNudge(x: CGFloat) {
        withAnimation(.timingCurve(0.24, 0.84, 0.28, 1, duration: 0.2)) {
            iconOffset = CGSize(width: x * 0.32, height: 0)
            iconRotation = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(125))

            withAnimation(.timingCurve(0.2, 0.88, 0.24, 1, duration: 0.34)) {
                iconOffset = .zero
            }
        }
    }
}

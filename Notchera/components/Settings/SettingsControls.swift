import SwiftUI

struct SettingsOptionCard<Content: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(background)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.16)) {
                    isHovering = hovering
                }
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(isSelected ? 0.06 : (isHovering ? 0.028 : 0.015)))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1 : 0.8)
            }
    }

    private var borderColor: Color {
        if isSelected {
            return Color(red: 0.62, green: 0.76, blue: 1).opacity(0.95)
        }

        return isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)
    }
}

struct SettingsIconOptionCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        SettingsOptionCard(title: title, isSelected: isSelected, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.72))
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var accentColor: Color = Color(red: 0.62, green: 0.76, blue: 1)
    var showsTicks: Bool = true
    var formatValue: (Double) -> String = { String(format: "%.1fs", $0) }

    @State private var isDragging = false
    @State private var dragValue: Double?

    private var displayedValue: Double {
        min(max(dragValue ?? value, range.lowerBound), range.upperBound)
    }

    private var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (displayedValue - range.lowerBound) / span
    }

    private var stepCount: Int {
        Int((range.upperBound - range.lowerBound) / step)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)

                Text(formatValue(clampedValue))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.9))
            }

            GeometryReader { geometry in
                let knobWidth: CGFloat = 24
                let knobHeight: CGFloat = 14
                let availableWidth = max(geometry.size.width - knobWidth, 1)
                let knobOffset = availableWidth * progress
                let dragGesture = DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(for: gesture.location.x, availableWidth: availableWidth, knobWidth: knobWidth)
                    }
                    .onEnded { gesture in
                        finishDragging(at: gesture.location.x, availableWidth: availableWidth, knobWidth: knobWidth)
                    }

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 8)

                    Capsule(style: .continuous)
                        .fill(accentColor)
                        .frame(width: max(knobOffset + knobWidth / 2, progress == 0 ? 0 : knobWidth / 2), height: 8)

                    if showsTicks {
                        HStack(spacing: 0) {
                            ForEach(0 ... stepCount, id: \.self) { index in
                                Circle()
                                    .fill(Color.white.opacity(index == 0 || index == stepCount ? 0.22 : 0.18))
                                    .frame(width: 3, height: 3)

                                if index < stepCount {
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.horizontal, knobWidth / 2)
                        .offset(y: 14)
                        .allowsHitTesting(false)
                    }

                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.98))
                        .frame(width: knobWidth, height: knobHeight)
                        .shadow(color: Color.black.opacity(0.22), radius: 6, y: 2)
                        .offset(x: knobOffset)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
                .gesture(dragGesture)
            }
            .frame(height: 30)
        }
        .padding(.vertical, 4)
        .animation(isDragging ? .linear(duration: 0.04) : .interactiveSpring(response: 0.18, dampingFraction: 0.88, blendDuration: 0.08), value: displayedValue)
    }

    private func updateValue(for locationX: CGFloat, availableWidth: CGFloat, knobWidth: CGFloat) {
        let normalized = min(max(locationX - knobWidth / 2, 0), availableWidth) / availableWidth
        let rawValue = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
        dragValue = min(max(rawValue, range.lowerBound), range.upperBound)

        let steppedValue = ((dragValue ?? rawValue) / step).rounded() * step
        value = min(max(steppedValue, range.lowerBound), range.upperBound)
    }

    private func finishDragging(at locationX: CGFloat, availableWidth: CGFloat, knobWidth: CGFloat) {
        updateValue(for: locationX, availableWidth: availableWidth, knobWidth: knobWidth)
        dragValue = nil
        isDragging = false
    }
}

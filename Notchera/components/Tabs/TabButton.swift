import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void

    @State private var isHovering = false

    private let buttonSize: CGFloat = 24

    private var cornerRadius: CGFloat {
        buttonSize * 0.28
    }

    private var backgroundColor: Color {
        (selected || isHovering) ? Color.gray.opacity(0.2) : .clear
    }

    private var iconColor: Color {
        selected ? .white : Color.white.opacity(0.5)
    }

    @ViewBuilder
    private var iconView: some View {
        if icon.hasPrefix("asset:") {
            Image(String(icon.dropFirst(6)))
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 11, height: 11)
                .opacity(selected ? 1 : 0.72)
        } else {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    var body: some View {
        Button(action: onClick) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    iconView
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    TabButton(label: "Music", icon: "music.note", selected: true) {
        print("Tapped")
    }
}

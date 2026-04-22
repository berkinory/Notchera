import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var animate = false
    @State private var textSize: CGSize = .zero

    private let spacing: CGFloat = 20

    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 1.5, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    private var needsScrolling: Bool {
        textSize.width > frameWidth + 0.5
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                measurementText

                if needsScrolling {
                    HStack(spacing: spacing) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: animate ? -(textSize.width + spacing) : 0)
                    .animation(
                        animate
                            ? .linear(duration: max(1.8, Double(textSize.width / 30)))
                            .delay(minDuration)
                            .repeatForever(autoreverses: false)
                            : .none,
                        value: animate
                    )
                } else {
                    marqueeLabel
                        .frame(width: frameWidth, alignment: .leading)
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .background(backgroundColor)
            .clipped()
            .onChange(of: text) { _, _ in
                restartAnimationIfNeeded()
            }
            .onChange(of: frameWidth) { _, _ in
                restartAnimationIfNeeded()
            }
            .onPreferenceChange(SizePreferenceKey.self) { size in
                let nextSize = CGSize(width: size.width, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                guard textSize != nextSize else { return }
                textSize = nextSize
                restartAnimationIfNeeded()
            }
        }
        .frame(height: textSize.height * 1.3)
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundColor(textColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measurementText: some View {
        marqueeLabel
            .hidden()
            .modifier(MeasureSizeModifier())
    }

    private func restartAnimationIfNeeded() {
        animate = false

        DispatchQueue.main.async {
            if needsScrolling {
                animate = true
            }
        }
    }
}

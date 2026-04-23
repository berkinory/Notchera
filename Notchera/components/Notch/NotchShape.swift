import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let safeTopCornerRadius = min(max(0, topCornerRadius), rect.width / 2, rect.height)
        let maxBottomCornerRadius = max(0, min(rect.height - safeTopCornerRadius, (rect.width - (safeTopCornerRadius * 2)) / 2))
        let safeBottomCornerRadius = min(max(0, bottomCornerRadius), maxBottomCornerRadius)

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + safeTopCornerRadius,
                y: rect.minY + safeTopCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + safeTopCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + safeTopCornerRadius,
                y: rect.maxY - safeBottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + safeTopCornerRadius + safeBottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + safeTopCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - safeTopCornerRadius - safeBottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - safeTopCornerRadius,
                y: rect.maxY - safeBottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - safeTopCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - safeTopCornerRadius,
                y: rect.minY + safeTopCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - safeTopCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}

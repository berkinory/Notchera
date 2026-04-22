import SwiftUI

enum ActivityType {
    case mediaPlayback
    case charging
}

struct LiveActivityModifier<Left: View, Right: View>: ViewModifier {
    let `for`: ActivityType
    let leftContent: () -> Left
    let rightContent: () -> Right

    func body(content: Content) -> some View {
        content
            .overlay(
                HStack {
                    leftContent()
                    Spacer()
                    rightContent()
                }
                .padding()
            )
    }
}

extension View {
    func liveActivity(
        for activityId: ActivityType,
        @ViewBuilder left: @escaping () -> some View,
        @ViewBuilder right: @escaping () -> some View
    ) -> some View {
        modifier(LiveActivityModifier(for: activityId, leftContent: left, rightContent: right))
    }
}

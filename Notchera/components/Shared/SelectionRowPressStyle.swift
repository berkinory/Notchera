import SwiftUI

struct SelectionRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.996 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

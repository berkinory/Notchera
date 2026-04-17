import SwiftUI

extension View {
    @ViewBuilder func conditionalModifier(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

import Defaults
import SwiftUI

struct NotcheraHeader: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    private var showHeaderControls: Bool {
        vm.notchState == .open
    }

    private var shouldShowTabs: Bool {
        true
    }

    private var leftTabs: [TabModel] {
        Array(tabs.prefix(3))
    }

    private var rightTabs: [TabModel] {
        Array(tabs.dropFirst(3))
    }

    private var centerFillColor: Color {
        NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear
    }

    var body: some View {
        HStack(spacing: 0) {
            if showHeaderControls, shouldShowTabs {
                TabSelectionView(items: leftTabs)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .zIndex(2)

                Rectangle()
                    .fill(centerFillColor)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }

                TabSelectionView(items: rightTabs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(2)
            } else if vm.notchState == .open {
                EmptyView()
            }
        }
        .opacity(vm.notchState == .closed ? 0 : 1)
        .blur(radius: vm.notchState == .closed ? 2 : 0)
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

#Preview {
    NotcheraHeader().environmentObject(NotcheraViewModel())
}

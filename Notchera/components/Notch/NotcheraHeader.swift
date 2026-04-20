import Defaults
import SwiftUI

struct NotcheraHeader: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    private var showHeaderControls: Bool {
        vm.notchState == .open
    }

    private var shouldShowTabs: Bool {
        !tvm.isEmpty || coordinator.alwaysShowTabs
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if showHeaderControls, shouldShowTabs, Defaults[.notchShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 2 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

#Preview {
    NotcheraHeader().environmentObject(NotcheraViewModel())
}

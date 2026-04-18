import Defaults
import SwiftUI

struct NotcheraHeader: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @State private var isHoveringSettings = false

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !tvm.isEmpty || coordinator.alwaysShowTabs, Defaults[.notchShelf] {
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

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if Defaults[.settingsIconInNotch] {
                        Button(action: {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }) {
                            RoundedRectangle(cornerRadius: 28 * 0.28, style: .continuous)
                                .fill(isHoveringSettings ? Color.gray.opacity(0.2) : .clear)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: "gear")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.5))
                                }
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 28 * 0.28, style: .continuous))
                        .onHover { hovering in
                            withAnimation(.smooth(duration: 0.18)) {
                                isHoveringSettings = hovering
                            }
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 2 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }
}

#Preview {
    NotcheraHeader().environmentObject(NotcheraViewModel())
}

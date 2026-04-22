import Defaults
import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared
    let items: [TabModel]

    var body: some View {
        tabGroup(items)
    }

    private func tabGroup(_ items: [TabModel]) -> some View {
        HStack(spacing: 1) {
            ForEach(items) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        if tab.view == .commandPalette {
                            coordinator.prepareCommandPalette(module: .appLauncher, rememberView: true)
                        } else {
                            coordinator.currentView = tab.view
                        }
                    }
                }
            }
        }
    }
}

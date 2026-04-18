import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Music", icon: "music.note", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
            }
        }
    }
}

#Preview {
    NotcheraHeader().environmentObject(NotcheraViewModel())
}

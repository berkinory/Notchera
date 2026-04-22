import SwiftUI

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .cancel)
    }

    func performDrop(info _: DropInfo) -> Bool {
        false
    }
}

import AppKit
import SwiftUI

struct ShelfView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 2

    var body: some View {
        panel
            .onDrop(of: [.fileURL], isTargeted: $vm.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
            .onChange(of: selection.selectedIDs) {
                updateQuickLookSelection()
            }
            .quickLookPresenter(using: quickLookService)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen, !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls = selectedItems.compactMap(\.fileURL)

        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    private var displayedItems: [ShelfItem] {
        Array(tvm.items.reversed())
    }

    private var itemRows: [[ShelfItem]] {
        stride(from: 0, to: displayedItems.count, by: 2).map { index in
            Array(displayedItems[index ..< min(index + 2, displayedItems.count)])
        }
    }

    private var allSelected: Bool {
        !tvm.items.isEmpty && selection.selectedIDs.count == tvm.items.count
    }

    private func toggleSelectAll() {
        if allSelected {
            selection.clear()
        } else {
            selection.selectAll(in: tvm.items)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding(10)
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard selection.shouldClearOnBackgroundTap else { return }
                selection.clear()
            }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: spacing) {
                        HStack(spacing: 0) {
                            Button(allSelected ? "Unselect All" : "Select All") {
                                toggleSelectAll()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 2)

                            Spacer(minLength: 0)
                        }
                        .frame(height: 14)

                        ForEach(Array(itemRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: spacing) {
                                ForEach(row) { item in
                                    ShelfItemView(item: item)
                                        .environmentObject(quickLookService)
                                }

                                if row.count == 1 {
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 37)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}

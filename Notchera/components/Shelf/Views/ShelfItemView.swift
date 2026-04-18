import AppKit
import Defaults
import QuickLook
import SwiftUI

struct ShelfItemView: View {
    let item: ShelfItem
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var selection = ShelfSelectionModel.shared
    @StateObject private var viewModel: ShelfItemViewModel
    @EnvironmentObject private var quickLookService: QuickLookService
    @State private var showStack = false
    @State private var cachedPreviewImage: NSImage?
    @State private var debouncedDropTarget = false

    private var isSelected: Bool {
        viewModel.isSelected
    }

    private var shouldHideDuringDrag: Bool {
        selection.isDragging && selection.isSelected(item.id) && false
    }

    init(item: ShelfItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: ShelfItemViewModel(item: item))
    }

    var body: some View {
        ZStack {
            if !shouldHideDuringDrag {
                VStack(alignment: .center, spacing: 2) {
                    iconView
                    textView
                }
                .frame(width: 105)
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .background(backgroundView)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)
                .animation(.easeInOut(duration: 0.1), value: isSelected)

                DraggableClickHandler(
                    item: item,
                    viewModel: viewModel,
                    cachedPreviewImage: $cachedPreviewImage,
                    dragPreviewContent: {
                        DragPreviewView(thumbnail: viewModel.thumbnail ?? item.icon, displayName: item.displayName)
                    },
                    onRightClick: viewModel.handleRightClick,
                    onClick: { event, nsview in
                        viewModel.handleClick(event: event, view: nsview)
                    }
                )
            } else {
                Color.clear
                    .frame(width: 105)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 5)
            }
        }
        .onChange(of: viewModel.isDropTargeted) { _, targeted in
            vm.dragDetectorTargeting = targeted
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                debouncedDropTarget = targeted
            }
        }
        .onAppear {
            Task {
                await viewModel.loadThumbnail()
                if cachedPreviewImage == nil {
                    cachedPreviewImage = await renderDragPreview()
                }
            }
            viewModel.onQuickLookRequest = { urls in
                quickLookService.show(urls: urls, selectFirst: true)
            }
        }
        .onChange(of: viewModel.thumbnail) { _, _ in
            Task {
                cachedPreviewImage = await renderDragPreview()
            }
        }
        .quickLookPresenter(using: quickLookService)
    }

    private var iconView: some View {
        Image(nsImage: viewModel.thumbnail ?? item.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    private var textView: some View {
        Text(item.displayName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(height: 30, alignment: .top)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        lineWidth: strokeWidth
                    )
            )
    }

    private var backgroundColor: Color {
        if debouncedDropTarget {
            Color.accentColor.opacity(0.25)
        } else if isSelected {
            Color.accentColor.opacity(0.15)
        } else {
            Color.clear
        }
    }

    private var strokeColor: Color {
        if debouncedDropTarget {
            Color.accentColor.opacity(0.9)
        } else if isSelected {
            Color.accentColor.opacity(0.8)
        } else {
            Color.clear
        }
    }

    private var strokeWidth: CGFloat {
        if debouncedDropTarget {
            3
        } else if isSelected {
            2
        } else {
            1
        }
    }

    @MainActor
    private func renderDragPreview() async -> NSImage {
        let content = DragPreviewView(thumbnail: viewModel.thumbnail ?? item.icon, displayName: item.displayName)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? (viewModel.thumbnail ?? item.icon)
    }
}

// MARK: - Draggable Click Handler with NSDraggingSource

private struct DraggableClickHandler<Content: View>: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfItemViewModel
    @Binding var cachedPreviewImage: NSImage?
    @ViewBuilder let dragPreviewContent: () -> Content
    let onRightClick: (NSEvent, NSView) -> Void
    let onClick: (NSEvent, NSView) -> Void

    func makeNSView(context _: Context) -> DraggableClickView {
        let view = DraggableClickView()
        view.item = item
        view.viewModel = viewModel
        view.dragPreviewImage = cachedPreviewImage ?? renderDragPreview()
        view.onRightClick = onRightClick
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DraggableClickView, context _: Context) {
        nsView.item = item
        nsView.viewModel = viewModel
        if let cached = cachedPreviewImage {
            nsView.dragPreviewImage = cached
        }
        nsView.onRightClick = onRightClick
        nsView.onClick = onClick
    }

    private func renderDragPreview() -> NSImage {
        let content = dragPreviewContent()
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if let nsImage = renderer.nsImage {
            return nsImage
        }

        return viewModel.thumbnail ?? item.icon
    }

    final class DraggableClickView: NSView, NSDraggingSource {
        var item: ShelfItem!
        weak var viewModel: ShelfItemViewModel?
        var dragPreviewImage: NSImage?
        var onRightClick: ((NSEvent, NSView) -> Void)?
        var onClick: ((NSEvent, NSView) -> Void)?

        private var mouseDownEvent: NSEvent?
        private let dragThreshold: CGFloat = 3.0
        private var draggedURLs: [URL] = []
        private var draggedItems: [ShelfItem] = []

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(event, self)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            onClick?(event, self)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent else {
                super.mouseDragged(with: event)
                return
            }

            let dragDistance = hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
            )

            if dragDistance > dragThreshold {
                startDragSession(with: event)
                self.mouseDownEvent = nil
            } else {
                super.mouseDragged(with: event)
            }
        }

        private func startDragSession(with event: NSEvent) {
            let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            let itemsToDrag: [ShelfItem] = if selectedItems.count > 1, selectedItems.contains(where: { $0.id == item.id }) {
                selectedItems
            } else {
                [item]
            }

            draggedItems = itemsToDrag

            var draggingItems: [NSDraggingItem] = []

            for dragItem in itemsToDrag {
                if let pasteboardItem = createPasteboardItem(for: dragItem) {
                    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

                    let image = dragPreviewImage ?? dragItem.icon
                    let imageFrame = NSRect(
                        x: 0,
                        y: 0,
                        width: image.size.width,
                        height: image.size.height
                    )
                    draggingItem.setDraggingFrame(imageFrame, contents: image)

                    draggingItems.append(draggingItem)
                }
            }

            guard !draggingItems.isEmpty else { return }

            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        private func createPasteboardItem(for item: ShelfItem) -> NSPasteboardItem? {
            let pasteboardItem = NSPasteboardItem()

            switch item.kind {
            case .file:
                guard let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) else {
                    pasteboardItem.setString(item.displayName, forType: .string)
                    return pasteboardItem
                }

                if url.startAccessingSecurityScopedResource() {
                    draggedURLs.append(url)
                    NSLog("🔐 Started security-scoped access for drag: \(url.path)")
                }

                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                pasteboardItem.setString(url.path, forType: .string)
                return pasteboardItem

            case let .text(string):
                pasteboardItem.setString(string, forType: .string)
                return pasteboardItem

            case let .link(url):
                pasteboardItem.setString(url.absoluteString, forType: .URL)
                pasteboardItem.setString(url.absoluteString, forType: .string)
                return pasteboardItem
            }
        }

        func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            if Defaults[.copyOnDrag] {
                return [.copy]
            }

            switch context {
            case .outsideApplication:
                return [.copy, .move]
            case .withinApplication:
                return [.copy, .move, .generic]
            @unknown default:
                return [.copy]
            }
        }

        func draggingSession(_: NSDraggingSession, willBeginAt _: NSPoint) {
            ShelfSelectionModel.shared.beginDrag()
        }

        func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
            ShelfSelectionModel.shared.endDrag()

            for url in draggedURLs {
                url.stopAccessingSecurityScopedResource()
                NSLog("🔐 Stopped security-scoped access after drag: \(url.path)")
            }
            draggedURLs.removeAll()

            if Defaults[.autoRemoveShelfItems], !operation.isEmpty {
                for item in draggedItems {
                    ShelfStateViewModel.shared.remove(item)
                }
            }
            draggedItems.removeAll()
        }

        func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
            false
        }
    }
}

import AppKit
import CoreServices
import Foundation
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShelfItemViewModel: ObservableObject {
    @Published private(set) var item: ShelfItem
    @Published var thumbnail: NSImage?
    @Published var isDropTargeted: Bool = false
    @Published var isRenaming: Bool = false
    @Published var draftTitle: String = ""
    private var sharingLifecycle: SharingLifecycleDelegate?
    private var quickShareLifecycle: SharingLifecycleDelegate?
    private var sharingAccessingURLs: [URL] = []
    private static var copiedURLs: [URL] = []

    private let selection = ShelfSelectionModel.shared

    init(item: ShelfItem) {
        self.item = item
        draftTitle = item.displayName
        Task { await loadThumbnail() }
    }

    var isSelected: Bool {
        selection.isSelected(item.id)
    }

    func loadThumbnail() async {
        guard let url = item.fileURL else { return }
        if let image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 30, height: 30)) {
            thumbnail = image
        }
    }

    func dragItemProvider() -> NSItemProvider {
        let selectedItems = selection.selectedItems(in: ShelfStateViewModel.shared.items)
        if selectedItems.count > 1, selectedItems.contains(where: { $0.id == item.id }) {
            return createMultiItemProvider(for: selectedItems)
        }
        return createItemProvider(for: item)
    }

    private func createItemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            let provider = NSItemProvider()
            if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                provider.registerObject(url as NSURL, visibility: .all)
            } else {
                provider.registerObject(item.displayName as NSString, visibility: .all)
            }
            return provider
        case let .text(string):
            return NSItemProvider(object: string as NSString)
        case let .link(url):
            return NSItemProvider(object: url as NSURL)
        }
    }

    private func createMultiItemProvider(for items: [ShelfItem]) -> NSItemProvider {
        let provider = NSItemProvider()
        var urls: [URL] = []
        var textItems: [String] = []
        for item in items {
            switch item.kind {
            case .file:
                if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                    urls.append(url)
                } else {
                    textItems.append(item.displayName)
                }
            case let .text(string):
                textItems.append(string)
            case .link:
                break
            }
        }
        if !urls.isEmpty {
            for url in urls {
                provider.registerObject(url as NSURL, visibility: .all)
            }
        }
        if !textItems.isEmpty {
            provider.registerObject(textItems.joined(separator: "\n") as NSString, visibility: .all)
        }
        return provider
    }

    func handleClick(event: NSEvent, view: NSView) {
        selection.suppressBackgroundClear()

        let flags = event.modifierFlags
        if flags.contains(.shift) {
            selection.shiftSelect(to: item, in: ShelfStateViewModel.shared.items)
        } else if flags.contains(.command) {
            selection.toggle(item)
        } else if flags.contains(.control) {
            handleRightClick(event: event, view: view)
        } else {
            if !selection.isSelected(item.id) { selection.selectSingle(item) }
        }
        if event.clickCount == 2 { handleDoubleClick() }
    }

    func handleRightClick(event: NSEvent, view: NSView) {
        selection.suppressBackgroundClear()

        if !selection.isSelected(item.id) { selection.selectSingle(item) }
        presentContextMenu(event: event, in: view)
    }

    func handleDoubleClick() {
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        guard !selected.isEmpty else { return }

        if selected.count > 1 {
            let alert = NSAlert()
            alert.messageText = "Open \(selected.count) items?"
            alert.informativeText = "This will open all selected shelf items."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open All")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        for it in selected {
            ShelfActionService.open(it)
        }
    }

    func shareItem(from view: NSView?) {
        Task {
            var itemsToShare: [Any] = []
            var fileURLs: [URL] = []
            if case let .text(text) = item.kind {
                itemsToShare.append(text)
            } else {
                for item in ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items) {
                    switch item.kind {
                    case .file:
                        if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) {
                            itemsToShare.append(url)
                            fileURLs.append(url)
                        }
                    case let .text(string):
                        itemsToShare.append(string)
                    case let .link(url):
                        itemsToShare.append(url)
                    }
                }
            }

            guard !itemsToShare.isEmpty else { return }

            stopSharingAccessingURLs()

            sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }

            let lifecycle = SharingStateManager.shared.makeDelegate { [weak self] in
                self?.sharingLifecycle = nil
                self?.stopSharingAccessingURLs()
            }
            self.sharingLifecycle = lifecycle

            let picker = NSSharingServicePicker(items: itemsToShare)
            picker.delegate = lifecycle
            lifecycle.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    private func stopSharingAccessingURLs() {
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }

    var onQuickLookRequest: (([URL]) -> Void)?

    private func ensureContextMenuSelection() {
        if !selection.isSelected(item.id) { selection.selectSingle(item) }
    }

    func presentContextMenu(event: NSEvent, in view: NSView) {
        ensureContextMenuSelection()
        let menu = NSMenu()

        func addMenuItem(title: String) {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menu.addItem(mi)
        }

        let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        let selectedFileURLs = selectedItems.compactMap(\.fileURL)
        let selectedLinkURLs: [URL] = selectedItems.compactMap { itm in
            if case let .link(url) = itm.kind { return url }
            return nil
        }
        let selectedFolderURLs = selectedFileURLs.filter { isDirectory($0) }
        let selectedOpenableURLs = selectedItems.compactMap { itm -> URL? in
            if let u = itm.fileURL { return isDirectory(u) ? nil : u }
            if case let .link(url) = itm.kind { return url }
            return nil
        }

        if !selectedOpenableURLs.isEmpty {
            addMenuItem(title: "Open")
        }

        if !selectedFileURLs.isEmpty { addMenuItem(title: "Show in Finder") }
        if !selectedFileURLs.isEmpty || !selectedLinkURLs.isEmpty {
            let quickLookItem = NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: "")
            menu.addItem(quickLookItem)

            let slideshowItem = NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: "")
            slideshowItem.isAlternate = true
            slideshowItem.keyEquivalentModifierMask = [.option]
            menu.addItem(slideshowItem)
        }

        menu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Share…")

        addMenuItem(title: "Copy")
        if !selectedFileURLs.isEmpty {
            let copyPathItem = NSMenuItem(title: "Copy Path", action: nil, keyEquivalent: "")
            copyPathItem.isAlternate = true
            copyPathItem.keyEquivalentModifierMask = [.option]
            menu.addItem(copyPathItem)
        }

        menu.addItem(NSMenuItem.separator())

        let removeItem = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
        removeItem.attributedTitle = NSAttributedString(
            string: "Remove",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.systemRed,
            ]
        )
        menu.addItem(removeItem)

        let actionTarget = MenuActionTarget(item: item, view: view, viewModel: self)

        for menuItem in menu.items {
            if menuItem.isSeparatorItem { continue }
            menuItem.target = actionTarget
            menuItem.action = #selector(MenuActionTarget.handle(_:))

            if let submenu = menuItem.submenu {
                for subItem in submenu.items {
                    if !subItem.isSeparatorItem {
                        subItem.target = actionTarget
                        subItem.action = #selector(MenuActionTarget.handle(_:))
                    }
                }
            }
        }

        menu.retainActionTarget(actionTarget)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func isDirectory(_ url: URL) -> Bool {
        url.accessSecurityScopedResource { scoped in
            (try? scoped.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
    }

    private final class MenuActionTarget: NSObject {
        let item: ShelfItem
        weak var view: NSView?
        unowned let viewModel: ShelfItemViewModel

        init(item: ShelfItem, view: NSView, viewModel: ShelfItemViewModel) {
            self.item = item
            self.view = view
            self.viewModel = viewModel
        }

        @MainActor @objc func handle(_ sender: NSMenuItem) {
            let title = sender.title

            switch title {
            case "Quick Look":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let urls: [URL] = selected.compactMap { item in
                    if let fileURL = item.fileURL {
                        return fileURL
                    }
                    if case let .link(url) = item.kind {
                        return url
                    }
                    return nil
                }
                if !urls.isEmpty {
                    viewModel.onQuickLookRequest?(urls)
                }

            case "Open":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected {
                    ShelfActionService.open(it)
                }

            case "Share…":
                viewModel.shareItem(from: view)

            case "Show in Finder":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                Task {
                    let urls = await selected.asyncCompactMap { item -> URL? in
                        if case .file = item.kind {
                            return await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
                        }
                        return nil
                    }
                    if !urls.isEmpty {
                        await urls.accessSecurityScopedResources { accessibleURLs in
                            NSWorkspace.shared.activateFileViewerSelecting(accessibleURLs)
                        }
                    }
                }

            case "Copy Path":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let paths = selected.compactMap { $0.fileURL?.path }
                if !paths.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                }

            case "Copy":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let pb = NSPasteboard.general

                for url in ShelfItemViewModel.copiedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
                ShelfItemViewModel.copiedURLs.removeAll()

                pb.clearContents()
                Task {
                    let fileURLs = await selected.asyncCompactMap { item -> URL? in
                        if case .file = item.kind {
                            return ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item)
                        }
                        return nil
                    }
                    if !fileURLs.isEmpty {
                        ShelfItemViewModel.copiedURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }
                        NSLog("🔐 Started security-scoped access for \(ShelfItemViewModel.copiedURLs.count) copied files")

                        pb.writeObjects(fileURLs as [NSURL])
                    } else {
                        let strings = selected.map(\.displayName)
                        if !strings.isEmpty {
                            pb.setString(strings.joined(separator: "\n"), forType: .string)
                        }
                    }
                }

            case "Remove":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected {
                    ShelfActionService.remove(it)
                }

            default:
                break
            }
        }
    }
}

private extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                result.append(transformed)
            }
        }
        return result
    }
}

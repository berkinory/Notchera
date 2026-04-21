import AppKit
import Defaults
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @ObservedObject private var appLauncher = AppLauncherManager.shared
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedRowID: String?
    @State private var pendingScrollRowID: String?
    @State private var pendingScrollAnchor: UnitPoint = .center

    private var appResults: [AppLauncherItem] {
        let query = coordinator.commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return appLauncher.filteredItems(for: query)
    }

    private var rootRows: [CommandPaletteRootRow] {
        appResults.map {
            CommandPaletteRootRow(
                id: "app.\($0.url.path)",
                title: $0.displayName,
                subtitle: $0.url.path,
                icon: nil,
                appItem: $0
            )
        }
    }

    private var rootRowIDs: [String] {
        rootRows.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            input
            content
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            CommandPaletteKeyboardHandler(
                isEnabled: coordinator.currentView == .commandPalette,
                onMoveUp: { moveSelection(by: -1) },
                onMoveDown: { moveSelection(by: 1) },
                onConfirm: { confirmSelection() }
            )
        }
        .background {
            NotchKeyboardFocusBridge(isEnabled: coordinator.currentView == .commandPalette)
        }
        .onAppear {
            appLauncher.loadIfNeeded()
            syncSelection(force: true)
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: coordinator.commandPaletteModule) { _, _ in
            syncSelection(force: true)
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: coordinator.commandPaletteQuery) { _, _ in
            syncSelection(force: true)
        }
        .onChange(of: rootRowIDs) { _, _ in
            syncSelection()
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .frame(width: 12)

            TextField(
                "Search apps",
                text: Binding(
                    get: { coordinator.commandPaletteQuery },
                    set: { coordinator.commandPaletteQuery = $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .focused($isSearchFieldFocused)
    }

    @ViewBuilder
    private var content: some View {
        if rootRows.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.72))

                Text("No results")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(rootRows) { row in
                            rootRow(row)
                                .id(row.id)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear {
                    scrollToSelectedRow(with: proxy, animated: false)
                }
                .onChange(of: pendingScrollRowID) { _, _ in
                    scrollToSelectedRow(with: proxy)
                }
            }
        }
    }

    private func rootRow(_ row: CommandPaletteRootRow) -> some View {
        let isSelected = selectedRowID == row.id

        return Button {
            activate(row)
        } label: {
            HStack(spacing: 8) {
                if let appItem = row.appItem {
                    Image(nsImage: appItem.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else if let icon = row.icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.62))
                        .frame(width: 10)
                }

                Text(row.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                selectedRowID = row.id
            }
        }
    }

    private func syncSelection(force: Bool = false) {
        guard !rootRows.isEmpty else {
            selectedRowID = nil
            return
        }

        if force || selectedRowID == nil || !rootRows.contains(where: { $0.id == selectedRowID }) {
            selectedRowID = rootRows.first?.id
        }
    }

    private func moveSelection(by offset: Int) {
        guard !rootRows.isEmpty else { return }

        let currentIndex = rootRows.firstIndex(where: { $0.id == selectedRowID }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), rootRows.count - 1)
        let nextRowID = rootRows[nextIndex].id
        selectedRowID = nextRowID
        pendingScrollAnchor = offset > 0 ? .bottom : .top
        pendingScrollRowID = nextRowID
    }

    private func confirmSelection() {
        guard let selectedRow = rootRows.first(where: { $0.id == selectedRowID }) else { return }
        activate(selectedRow)
    }

    private func scrollToSelectedRow(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedRowID else { return }

        let action = {
            proxy.scrollTo(selectedRowID, anchor: pendingScrollAnchor)
        }

        if animated {
            withAnimation(.timingCurve(0.22, 0.88, 0.32, 1, duration: 0.22)) {
                action()
            }
        } else {
            action()
        }

        if pendingScrollRowID == selectedRowID {
            pendingScrollRowID = nil
        }
    }

    private func activate(_ row: CommandPaletteRootRow) {
        guard let appItem = row.appItem else { return }

        NSWorkspace.shared.openApplication(at: appItem.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error == nil {
                Task { @MainActor in
                    appLauncher.recordLaunch(for: appItem)
                }
            }
        }

        NotificationCenter.default.post(
            name: .endClipboardKeyboardNavigation,
            object: nil,
            userInfo: ["shouldCloseNotch": true]
        )
    }
}

private struct NotchKeyboardFocusBridge: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            updateWindow(for: nsView)
        }
    }

    private func updateWindow(for view: NSView) {
        guard let panel = view.window as? NotcheraSkyLightWindow else { return }

        panel.setClipboardKeyboardFocusEnabled(isEnabled)

        guard isEnabled else { return }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}

private struct CommandPaletteRootRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let appItem: AppLauncherItem?

    init(id: String, title: String, subtitle: String?, icon: String?, appItem: AppLauncherItem? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.appItem = appItem
    }
}

private struct CommandPaletteKeyboardHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onMoveUp: onMoveUp, onMoveDown: onMoveDown, onConfirm: onConfirm)
    }

    func makeNSView(context: Context) -> CommandPaletteKeyMonitorHostView {
        let view = CommandPaletteKeyMonitorHostView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_: CommandPaletteKeyMonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
    }

    static func dismantleNSView(_: CommandPaletteKeyMonitorHostView, coordinator: Coordinator) {
        coordinator.stop()
    }
}

private final class CommandPaletteKeyMonitorHostView: NSView {}

private extension CommandPaletteKeyboardHandler {
    final class Coordinator {
        var isEnabled: Bool
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onConfirm: () -> Void

        private var monitor: Any?

        init(isEnabled: Bool, onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onConfirm: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onConfirm = onConfirm
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, isEnabled else { return event }

                switch Int(event.keyCode) {
                case 125:
                    onMoveDown()
                    return nil
                case 126:
                    onMoveUp()
                    return nil
                case 36, 76:
                    onConfirm()
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct ClipboardResultsView: View {
    let isActive: Bool

    @ObservedObject private var clipboardHistoryManager = ClipboardHistoryManager.shared
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @Default(.clipboardHistoryRetention) private var retention
    @State private var hoveredItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollAnchor: UnitPoint = .center
    @State private var copiedItemID: ClipboardHistoryItem.ID?
    @State private var copyResetTask: Task<Void, Never>?

    private var itemIDs: [ClipboardHistoryItem.ID] {
        clipboardHistoryManager.items.map(\.id)
    }

    private var keyboardNavigationEnabled: Bool {
        isActive && (coordinator.currentView == .commandPalette || coordinator.currentView == .clipboard)
    }

    var body: some View {
        Group {
            if clipboardHistoryManager.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.72))

                    Text("No clipboard items yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(clipboardHistoryManager.items) { item in
                                clipboardRow(for: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onAppear {
                        scrollToHoveredItem(with: proxy, animated: false)
                    }
                    .onChange(of: pendingScrollItemID) { _, _ in
                        scrollToHoveredItem(with: proxy)
                    }
                }
            }
        }
        .background {
            ClipboardKeyboardHandler(
                isEnabled: keyboardNavigationEnabled,
                onMoveUp: { moveSelection(by: -1) },
                onMoveDown: { moveSelection(by: 1) },
                onConfirm: { copyHoveredItem() },
                onCancel: { endKeyboardNavigation(shouldCloseNotch: true) }
            )
        }
        .onAppear {
            clipboardHistoryManager.pruneExpiredItems()
            pendingScrollAnchor = .center
            selectFirstItemIfNeeded()
        }
        .onChange(of: retention) { _, _ in
            clipboardHistoryManager.pruneExpiredItems()
        }
        .onChange(of: isActive) { _, _ in
            selectFirstItemIfNeeded(force: true)
        }
        .onChange(of: itemIDs) { _, _ in
            syncHoveredItem()
        }
    }

    private func clipboardRow(for item: ClipboardHistoryItem) -> some View {
        let isHovered = hoveredItemID == item.id
        let isCopied = copiedItemID == item.id

        return Button {
            clipboardHistoryManager.copy(item)
            showCopiedState(for: item.id)
            endKeyboardNavigation()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isFile ? "text.document" : "character.cursor.ibeam")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.62))
                    .frame(width: 10)

                Text(displayText(for: item))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isCopied ? "checkmark.app.fill" : "doc.on.doc")
                    .font(.system(size: isCopied ? 11 : 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 12)
                    .opacity(isHovered || isCopied ? 1 : 0)
                    .scaleEffect(isCopied ? 1.05 : 1)
                    .animation(.spring(response: 0.42, dampingFraction: 0.88), value: isCopied)
                    .animation(.easeOut(duration: 0.18), value: isHovered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            guard !keyboardNavigationEnabled else { return }
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
    }

    private func displayText(for item: ClipboardHistoryItem) -> String {
        if item.isFile {
            return trimmedFileName(item.displayText)
        }

        let content = item.displayText
        let lines = content.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !firstLine.isEmpty else { return content.replacingOccurrences(of: "\n", with: " ") }
        return lines.count > 1 ? "\(firstLine)..." : firstLine
    }

    private func trimmedFileName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let fileExtension = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent

        guard !fileExtension.isEmpty else {
            return fileName
        }

        let visiblePrefixCount = min(6, baseName.count)
        let prefix = String(baseName.prefix(visiblePrefixCount))
        return "\(prefix)... .\(fileExtension)"
    }

    private func showCopiedState(for itemID: ClipboardHistoryItem.ID) {
        copyResetTask?.cancel()
        copiedItemID = itemID

        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if copiedItemID == itemID {
                    copiedItemID = nil
                }
            }
        }
    }

    private func selectFirstItemIfNeeded(force: Bool = false) {
        guard !clipboardHistoryManager.items.isEmpty else {
            hoveredItemID = nil
            return
        }

        if force || hoveredItemID == nil {
            hoveredItemID = clipboardHistoryManager.items.first?.id
        }
    }

    private func syncHoveredItem() {
        guard !clipboardHistoryManager.items.isEmpty else {
            hoveredItemID = nil
            return
        }

        guard let hoveredItemID,
              clipboardHistoryManager.items.contains(where: { $0.id == hoveredItemID })
        else {
            hoveredItemID = clipboardHistoryManager.items.first?.id
            return
        }
    }

    private func moveSelection(by offset: Int) {
        guard !clipboardHistoryManager.items.isEmpty else { return }

        let items = clipboardHistoryManager.items
        let currentIndex = items.firstIndex(where: { $0.id == hoveredItemID }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        let nextItemID = items[nextIndex].id
        hoveredItemID = nextItemID
        pendingScrollAnchor = offset > 0 ? .bottom : .top
        pendingScrollItemID = nextItemID
    }

    private func scrollToHoveredItem(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let hoveredItemID else { return }

        let action = {
            proxy.scrollTo(hoveredItemID, anchor: pendingScrollAnchor)
        }

        if animated {
            withAnimation(.timingCurve(0.22, 0.88, 0.32, 1, duration: 0.22)) {
                action()
            }
        } else {
            action()
        }

        if pendingScrollItemID == hoveredItemID {
            pendingScrollItemID = nil
        }
    }

    private func copyHoveredItem() {
        guard let hoveredItemID,
              let item = clipboardHistoryManager.items.first(where: { $0.id == hoveredItemID })
        else {
            return
        }

        clipboardHistoryManager.copy(item)
        showCopiedState(for: item.id)

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                endKeyboardNavigation(shouldCloseNotch: true)
            }
        }
    }

    private func endKeyboardNavigation(shouldCloseNotch: Bool = false) {
        NotificationCenter.default.post(
            name: .endClipboardKeyboardNavigation,
            object: nil,
            userInfo: ["shouldCloseNotch": shouldCloseNotch]
        )
    }
}

private struct ClipboardKeyboardHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onMoveUp: onMoveUp, onMoveDown: onMoveDown, onConfirm: onConfirm, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> KeyMonitorHostView {
        let view = KeyMonitorHostView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_: KeyMonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_: KeyMonitorHostView, coordinator: Coordinator) {
        coordinator.stop()
    }
}

private final class KeyMonitorHostView: NSView {}

private extension ClipboardKeyboardHandler {
    final class Coordinator {
        var isEnabled: Bool
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onConfirm: () -> Void
        var onCancel: () -> Void

        private var monitor: Any?

        init(isEnabled: Bool, onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onConfirm = onConfirm
            self.onCancel = onCancel
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, isEnabled else { return event }

                switch Int(event.keyCode) {
                case 125:
                    onMoveDown()
                    return nil
                case 126:
                    onMoveUp()
                    return nil
                case 36, 76:
                    onConfirm()
                    return nil
                case 53:
                    onCancel()
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

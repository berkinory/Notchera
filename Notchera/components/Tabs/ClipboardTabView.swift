import AppKit
import Defaults
import SwiftUI

struct ClipboardTabView: View {
    @ObservedObject private var clipboardHistoryManager = ClipboardHistoryManager.shared
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @Default(.clipboardHistoryRetention) private var retention
    @State private var hoveredItemID: ClipboardHistoryItem.ID?
    @State private var copiedItemID: ClipboardHistoryItem.ID?
    @State private var copyResetTask: Task<Void, Never>?
    @State private var suppressMouseHover = false
    @State private var hoverSuppressionTask: Task<Void, Never>?

    private var filteredItems: [ClipboardHistoryItem] {
        let rawQuery = coordinator.clipboardSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty else { return clipboardHistoryManager.items }

        let normalizedQuery = normalizedClipboardSearchQuery(rawQuery)
        let shouldUseNormalizedSearch = rawQuery.allSatisfy { $0.isLetter || $0.isNumber || $0.isWhitespace }
        let shouldSearchFilePaths = rawQuery.contains("/") || rawQuery.contains(".") || rawQuery.contains("~") || rawQuery.contains(":")

        return clipboardHistoryManager.items.filter { item in
            if primaryRawSearchText(for: item).localizedCaseInsensitiveContains(rawQuery) {
                return true
            }

            if shouldSearchFilePaths,
               filePathSearchText(for: item).localizedCaseInsensitiveContains(rawQuery)
            {
                return true
            }

            guard shouldUseNormalizedSearch, !normalizedQuery.isEmpty else { return false }
            return primaryNormalizedSearchText(for: item).contains(normalizedQuery)
        }
    }

    private var itemIDs: [ClipboardHistoryItem.ID] {
        filteredItems.map(\.id)
    }

    private var keyboardNavigationEnabled: Bool {
        coordinator.currentView == .clipboard
    }

    private var keyboardInputActive: Bool {
        keyboardNavigationEnabled && coordinator.notchKeyboardDismissActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                    .frame(width: 12)

                TimelineView(.periodic(from: .now, by: 0.42)) { context in
                    let showsCaret = keyboardInputActive
                        && Int(context.date.timeIntervalSinceReferenceDate / 0.42).isMultiple(of: 2)

                    HStack(spacing: 0) {
                        if coordinator.clipboardSearchQuery.isEmpty {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 1.25, height: 14)
                                .padding(.trailing, 1)
                                .opacity(showsCaret ? 1 : 0)

                            Text("Search clipboard")
                                .foregroundStyle(Color.white.opacity(0.3))
                        } else {
                            Text(verbatim: coordinator.clipboardSearchQuery)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 1.25, height: 14)
                                .padding(.leading, -0.5)
                                .opacity(showsCaret ? 1 : 0)
                        }
                    }
                    .font(.system(size: 11.5, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.7
                    )
            }

            if filteredItems.isEmpty {
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
                        LazyVStack(spacing: 4) {
                            ForEach(filteredItems) { item in
                                clipboardRow(for: item)
                                    .id(item.id)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onAppear {
                        scrollToHoveredItem(with: proxy, animated: false)
                    }
                    .onChange(of: hoveredItemID) { _, _ in
                        scrollToHoveredItem(with: proxy, animated: false)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.top, 0)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            clipboardHistoryManager.pruneExpiredItems()
            selectFirstItemIfNeeded()
        }
        .onChange(of: retention) { _, _ in
            clipboardHistoryManager.pruneExpiredItems()
        }
        .onChange(of: coordinator.currentView) { _, newValue in
            guard newValue == .clipboard else { return }
            selectFirstItemIfNeeded(force: true)
        }
        .onChange(of: coordinator.clipboardSearchQuery) { _, _ in
            if keyboardInputActive {
                temporarilySuppressMouseHover()
            }
            syncHoveredItem(force: true)
        }
        .onChange(of: itemIDs) { _, _ in
            syncHoveredItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardMoveUp)) { notification in
            guard keyboardNavigationEnabled,
                  notification.object as? NotchKeyboardInterceptor.Mode == .clipboard
            else { return }
            moveSelection(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardMoveDown)) { notification in
            guard keyboardNavigationEnabled,
                  notification.object as? NotchKeyboardInterceptor.Mode == .clipboard
            else { return }
            moveSelection(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardConfirm)) { notification in
            guard keyboardNavigationEnabled,
                  notification.object as? NotchKeyboardInterceptor.Mode == .clipboard
            else { return }
            copyHoveredItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardAppendText)) { notification in
            guard keyboardNavigationEnabled,
                  notification.object as? NotchKeyboardInterceptor.Mode == .clipboard,
                  let text = notification.userInfo?["text"] as? String
            else { return }
            coordinator.clipboardSearchQuery.append(text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardBackspace)) { notification in
            guard keyboardNavigationEnabled,
                  notification.object as? NotchKeyboardInterceptor.Mode == .clipboard
            else { return }

            if notification.userInfo?["clearAll"] as? Bool == true {
                coordinator.clipboardSearchQuery = ""
            } else {
                removeLastCharacter(from: &coordinator.clipboardSearchQuery)
            }
        }
        .onDisappear {
            copyResetTask?.cancel()
            hoverSuppressionTask?.cancel()
            hoverSuppressionTask = nil
            suppressMouseHover = false
        }
    }

    private func clipboardRow(for item: ClipboardHistoryItem) -> some View {
        ClipboardHistoryRowView(
            id: item.id,
            title: displayText(for: item),
            icon: item.isFile ? "text.document" : "character.cursor.ibeam",
            isSelected: hoveredItemID == item.id,
            isHovered: hoveredItemID == item.id,
            isCopied: copiedItemID == item.id,
            action: {
                clipboardHistoryManager.activateSelection(for: item)
                showCopiedState(for: item.id)
                endKeyboardNavigation(shouldCloseNotch: Defaults[.clipboardSelectionAction] == .paste)
            },
            onHover: { hovering in
                guard !suppressMouseHover else { return }
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        )
        .equatable()
    }

    private func removeLastCharacter(from string: inout String) {
        guard !string.isEmpty else { return }
        string.removeLast()
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

    private func primaryNormalizedSearchText(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text:
            item.searchText
        case let .file(path):
            normalizedClipboardSearchQuery(URL(fileURLWithPath: path).lastPathComponent)
        }
    }

    private func primaryRawSearchText(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case let .text(content):
            content
        case let .file(path):
            URL(fileURLWithPath: path).lastPathComponent
        }
    }

    private func filePathSearchText(for item: ClipboardHistoryItem) -> String {
        guard case let .file(path) = item.kind else { return "" }
        return path
    }

    private func normalizedClipboardSearchQuery(_ query: String) -> String {
        let folded = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let pieces = folded.split { character in
            !character.isLetter && !character.isNumber
        }

        return pieces.joined(separator: " ")
    }

    private func trimmedFileName(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let fileExtension = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent

        guard !fileExtension.isEmpty else {
            return fileName
        }

        guard baseName.count > 10 else {
            return fileName
        }

        let visiblePrefixCount = 6
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

    private func temporarilySuppressMouseHover() {
        hoverSuppressionTask?.cancel()
        suppressMouseHover = true

        hoverSuppressionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                suppressMouseHover = false
            }
        }
    }

    private func selectFirstItemIfNeeded(force: Bool = false) {
        guard !filteredItems.isEmpty else {
            hoveredItemID = nil
            return
        }

        if force || hoveredItemID == nil {
            hoveredItemID = filteredItems.first?.id
        }
    }

    private func syncHoveredItem(force: Bool = false) {
        guard !filteredItems.isEmpty else {
            hoveredItemID = nil
            return
        }

        if force {
            hoveredItemID = filteredItems.first?.id
            return
        }

        guard let hoveredItemID,
              filteredItems.contains(where: { $0.id == hoveredItemID })
        else {
            hoveredItemID = filteredItems.first?.id
            return
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }

        let items = filteredItems
        let currentIndex = items.firstIndex(where: { $0.id == hoveredItemID }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        guard nextIndex != currentIndex else { return }
        temporarilySuppressMouseHover()
        hoveredItemID = items[nextIndex].id
    }

    private func scrollToHoveredItem(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let hoveredItemID else { return }

        let action = {
            proxy.scrollTo(hoveredItemID)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                action()
            }
        } else {
            action()
        }
    }

    private func copyHoveredItem() {
        guard let hoveredItemID,
              let item = filteredItems.first(where: { $0.id == hoveredItemID })
        else {
            return
        }

        clipboardHistoryManager.activateSelection(for: item)
        showCopiedState(for: item.id)
        endKeyboardNavigation(shouldCloseNotch: true)
    }

    private func endKeyboardNavigation(shouldCloseNotch: Bool = false) {
        NotificationCenter.default.post(
            name: .endClipboardKeyboardNavigation,
            object: nil,
            userInfo: ["shouldCloseNotch": shouldCloseNotch]
        )
    }
}

private struct ClipboardHistoryRowView: View, Equatable {
    let id: ClipboardHistoryItem.ID
    let title: String
    let icon: String
    let isSelected: Bool
    let isHovered: Bool
    let isCopied: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.icon == rhs.icon
            && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
            && lhs.isCopied == rhs.isCopied
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                iconView

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isCopied ? "checkmark.app.fill" : "doc.on.doc")
                    .font(.system(size: isCopied ? 10.5 : 9.5, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.white.opacity(0.9) : Color.white.opacity(0.7))
                    .frame(width: 12)
                    .opacity(isSelected || isCopied ? 1 : 0)
                    .scaleEffect(isCopied ? 1.03 : 1)
                    .animation(.easeOut(duration: 0.12), value: isCopied)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .background(backgroundShape.fill(backgroundFill))
            .overlay {
                backgroundShape
                    .strokeBorder(borderColor, lineWidth: 0.6)
            }
            .contentShape(backgroundShape)
        }
        .buttonStyle(SelectionRowPressStyle())
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover(perform: onHover)
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Color.white.opacity(0.082)
        }

        if isHovered {
            return Color.white.opacity(0.055)
        }

        return Color.white.opacity(0.036)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.white.opacity(0.095)
        }

        if isHovered {
            return Color.white.opacity(0.06)
        }

        return Color.white.opacity(0.03)
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.045))

            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary.opacity(0.62))
        }
        .frame(width: 18, height: 18)
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

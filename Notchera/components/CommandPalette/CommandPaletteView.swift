import AppKit
import Defaults
import IOKit.pwr_mgt
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @ObservedObject private var appLauncher = AppLauncherManager.shared
    @ObservedObject private var preventSleepManager = PreventSleepManager.shared
    @State private var selectedRowID: String?
    @State private var hoveredRowID: String?
    @State private var suppressMouseHover = false
    @State private var hoverSuppressionTask: Task<Void, Never>?

    private var trimmedQuery: String {
        coordinator.commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var appResults: [AppLauncherItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        return appLauncher.filteredItems(for: trimmedQuery)
    }

    private var rootRows: [CommandPaletteRootRow] {
        var rows = commandRows(for: trimmedQuery)

        rows.append(contentsOf: appResults.map {
            CommandPaletteRootRow(
                id: "app.\($0.url.path)",
                title: $0.displayName,
                subtitle: $0.url.path,
                icon: nil,
                appItem: $0,
                action: nil
            )
        })

        if let googleSearchRow {
            rows.append(googleSearchRow)
        }

        return rows
    }

    private var googleSearchRow: CommandPaletteRootRow? {
        guard !trimmedQuery.isEmpty else { return nil }

        return CommandPaletteRootRow(
            id: "action.google-search.\(trimmedQuery)",
            title: "Search Web for \"\(trimmedQuery)\"",
            subtitle: nil,
            imageAssetName: "google",
            icon: nil,
            appItem: nil,
            action: .googleSearch(trimmedQuery),
            usageKey: nil
        )
    }

    private var rootRowIDs: [String] {
        rootRows.map(\.id)
    }

    private var keyboardInputActive: Bool {
        coordinator.currentView == .commandPalette && coordinator.notchKeyboardDismissActive
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
        .onAppear {
            appLauncher.loadIfNeeded()
            _ = preventSleepManager
            syncSelection(force: true)
        }
        .onChange(of: coordinator.commandPaletteModule) { _, _ in
            syncSelection(force: true)
        }
        .onChange(of: coordinator.commandPaletteQuery) { _, _ in
            syncSelection(force: true)
        }
        .onChange(of: rootRowIDs) { _, _ in
            syncSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardMoveUp)) { notification in
            guard coordinator.currentView == .commandPalette,
                  notification.object as? NotchKeyboardInterceptor.Mode == .commandPalette
            else { return }
            moveSelection(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardMoveDown)) { notification in
            guard coordinator.currentView == .commandPalette,
                  notification.object as? NotchKeyboardInterceptor.Mode == .commandPalette
            else { return }
            moveSelection(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardConfirm)) { notification in
            guard coordinator.currentView == .commandPalette,
                  notification.object as? NotchKeyboardInterceptor.Mode == .commandPalette
            else { return }
            confirmSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardAppendText)) { notification in
            guard coordinator.currentView == .commandPalette,
                  notification.object as? NotchKeyboardInterceptor.Mode == .commandPalette,
                  let text = notification.userInfo?["text"] as? String
            else { return }
            coordinator.commandPaletteQuery.append(text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchKeyboardBackspace)) { notification in
            guard coordinator.currentView == .commandPalette,
                  notification.object as? NotchKeyboardInterceptor.Mode == .commandPalette
            else { return }

            if notification.userInfo?["clearAll"] as? Bool == true {
                coordinator.commandPaletteQuery = ""
            } else {
                removeLastCharacter(from: &coordinator.commandPaletteQuery)
            }
        }
        .onDisappear {
            hoverSuppressionTask?.cancel()
            hoverSuppressionTask = nil
            suppressMouseHover = false
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .frame(width: 12)

            TimelineView(.periodic(from: .now, by: 0.42)) { context in
                let showsCaret = keyboardInputActive
                    && Int(context.date.timeIntervalSinceReferenceDate / 0.42).isMultiple(of: 2)

                HStack(spacing: 0) {
                    if coordinator.commandPaletteQuery.isEmpty {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 1.25, height: 14)
                            .padding(.trailing, 1)
                            .opacity(showsCaret ? 1 : 0)

                        Text("Search apps and commands")
                            .foregroundStyle(Color.white.opacity(0.3))
                    } else {
                        Text(verbatim: coordinator.commandPaletteQuery)
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
    }

    @ViewBuilder
    private var content: some View {
        if rootRows.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "command")
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
                    LazyVStack(spacing: 4) {
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
                .onChange(of: selectedRowID) { _, _ in
                    scrollToSelectedRow(with: proxy, animated: false)
                }
            }
        }
    }

    private func removeLastCharacter(from string: inout String) {
        guard !string.isEmpty else { return }
        string.removeLast()
    }

    private func rootRow(_ row: CommandPaletteRootRow) -> some View {
        CommandPaletteRowView(
            row: row,
            isSelected: selectedRowID == row.id,
            isHovered: hoveredRowID == row.id,
            action: {
                activate(row)
            },
            onHover: { hovering in
                guard !suppressMouseHover else { return }

                if hovering {
                    hoveredRowID = row.id
                    selectedRowID = row.id
                } else if hoveredRowID == row.id {
                    hoveredRowID = nil
                }
            }
        )
        .equatable()
    }

    private func commandRows(for query: String) -> [CommandPaletteRootRow] {
        var rows: [ScoredCommandPaletteRow] = []

        if let calculatorResult = CalculatorEvaluator.evaluate(query), !query.isEmpty {
            rows.append(
                .init(
                    score: 20000 + commandUsageBoost(for: "calculator.copy-result"),
                    row: CommandPaletteRootRow(
                        id: "calculator.\(calculatorResult.displayValue)",
                        title: calculatorResult.displayValue,
                        icon: "equal",
                        appItem: nil,
                        action: .copyToClipboard(calculatorResult.displayValue),
                        usageKey: "calculator.copy-result"
                    )
                )
            )
        }

        rows.append(contentsOf: systemCommandRows(for: query))

        if query.isEmpty {
            return rows.map(\.row)
        }

        return rows
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.row.title.localizedCaseInsensitiveCompare(rhs.row.title) == .orderedAscending
            }
            .map(\.row)
    }

    private func systemCommandRows(for query: String) -> [ScoredCommandPaletteRow] {
        var rows: [ScoredCommandPaletteRow] = []

        let preventSleepAliases = ["prevent sleep", "awake", "caffeine", "caffeinate", "insomnia", "enable", "disable", "amphetamine"]
        if query.isEmpty || matches(query, aliases: preventSleepAliases) {
            rows.append(
                .init(
                    score: scoredCommandBase(query: query, aliases: preventSleepAliases, baseScore: 9600, usageKey: "prevent-sleep.toggle", emptyScore: 8600),
                    row: CommandPaletteRootRow(
                        id: "action.prevent-sleep.toggle",
                        title: "Prevent Sleep",
                        subtitle: preventSleepManager.isActive ? "On" : "Off",
                        icon: preventSleepManager.isActive ? "poweroutlet.type.b.fill" : "poweroutlet.type.g.fill",
                        appItem: nil,
                        action: .togglePreventSleep,
                        usageKey: "prevent-sleep.toggle"
                    )
                )
            )
        }

        let lockAliases = ["lock", "lock screen", "screen lock", "secure screen"]
        if query.isEmpty || matches(query, aliases: lockAliases) {
            rows.append(
                .init(
                    score: scoredCommandBase(query: query, aliases: lockAliases, baseScore: 9200, usageKey: "system.lock-screen", emptyScore: 8200),
                    row: CommandPaletteRootRow(
                        id: "action.system.lock-screen",
                        title: "Lock",
                        icon: "lock.fill",
                        appItem: nil,
                        action: .lockScreen,
                        usageKey: "system.lock-screen"
                    )
                )
            )
        }

        let sleepAliases = ["sleep", "sleep mac", "sleep computer", "put mac to sleep"]
        if query.isEmpty || matches(query, aliases: sleepAliases) {
            rows.append(
                .init(
                    score: scoredCommandBase(query: query, aliases: sleepAliases, baseScore: 9000, usageKey: "system.sleep-mac", emptyScore: 8000),
                    row: CommandPaletteRootRow(
                        id: "action.system.sleep-mac",
                        title: "Sleep",
                        subtitle: "Put Mac to sleep",
                        icon: "moon.zzz.fill",
                        appItem: nil,
                        action: .sleepMac,
                        usageKey: "system.sleep-mac"
                    )
                )
            )
        }

        return rows
    }

    private func matches(_ query: String, aliases: [String]) -> Bool {
        score(query: query, aliases: aliases, baseScore: 1) > 0
    }

    private func scoredCommandBase(query: String, aliases: [String], baseScore: Int, usageKey: String, emptyScore: Int) -> Int {
        if query.isEmpty {
            return emptyScore
        }

        let matchedScore = score(query: query, aliases: aliases, baseScore: baseScore)
        guard matchedScore > 0 else { return 0 }
        return matchedScore + commandUsageBoost(for: usageKey)
    }

    private func commandUsageBoost(for usageKey: String) -> Int {
        CommandPaletteUsageManager.shared.usageBoost(for: usageKey)
    }

    private func score(query: String, aliases: [String], baseScore: Int) -> Int {
        guard !aliases.isEmpty else { return 0 }
        guard !query.isEmpty else { return baseScore }

        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return baseScore }

        let normalizedAliases = aliases.map(normalize)

        if normalizedAliases.contains(normalizedQuery) {
            return baseScore + 700
        }

        if normalizedAliases.contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return baseScore + 420
        }

        if normalizedAliases.contains(where: { $0.contains(normalizedQuery) }) {
            return baseScore + 260
        }

        let queryParts = normalizedQuery.split(separator: " ").map(String.init)
        if queryParts.allSatisfy({ part in
            normalizedAliases.contains(where: { $0.contains(part) })
        }) {
            return baseScore + 120
        }

        return 0
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: " ")
    }

    private func syncSelection(force: Bool = false) {
        guard !rootRows.isEmpty else {
            selectedRowID = nil
            hoveredRowID = nil
            return
        }

        if force || selectedRowID == nil || !rootRows.contains(where: { $0.id == selectedRowID }) {
            selectedRowID = rootRows.first?.id
        }

        if let hoveredRowID, !rootRows.contains(where: { $0.id == hoveredRowID }) {
            self.hoveredRowID = nil
        }
    }

    private func moveSelection(by offset: Int) {
        guard !rootRows.isEmpty else { return }

        let currentIndex = rootRows.firstIndex(where: { $0.id == selectedRowID }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), rootRows.count - 1)
        guard nextIndex != currentIndex else { return }
        temporarilySuppressMouseHover()
        selectedRowID = rootRows[nextIndex].id
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

    private func confirmSelection() {
        guard let selectedRow = rootRows.first(where: { $0.id == selectedRowID }) else { return }
        activate(selectedRow)
    }

    private func scrollToSelectedRow(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedRowID else { return }

        let action = {
            proxy.scrollTo(selectedRowID)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                action()
            }
        } else {
            action()
        }
    }

    private func activate(_ row: CommandPaletteRootRow) {
        let shouldCloseAfterActivation = !isMouseTriggeredActivation

        if let appItem = row.appItem {
            NSWorkspace.shared.openApplication(at: appItem.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error == nil {
                    Task { @MainActor in
                        appLauncher.recordLaunch(for: appItem)
                    }
                }
            }

            if shouldCloseAfterActivation {
                closePalette()
            }
            return
        }

        guard let action = row.action else { return }

        if let usageKey = row.usageKey {
            CommandPaletteUsageManager.shared.recordUse(for: usageKey)
        }

        Task { @MainActor in
            await perform(action, shouldClosePalette: shouldCloseAfterActivation)
        }
    }

    @MainActor
    private func perform(_ action: CommandPaletteAction, shouldClosePalette: Bool) async {
        switch action {
        case let .copyToClipboard(value):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            if shouldClosePalette {
                closePalette()
            }
        case let .googleSearch(query):
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
            ]

            if let url = components.url {
                NSWorkspace.shared.open(url)
            }

            if shouldClosePalette {
                closePalette()
            }
        case .togglePreventSleep:
            preventSleepManager.toggle()
            if shouldClosePalette {
                closePalette()
            }
        case let .enablePreventSleep(duration):
            preventSleepManager.enable(for: duration)
            if shouldClosePalette {
                closePalette()
            }
        case .lockScreen:
            await CommandPaletteSystemActions.lockScreen()
            closePalette()
        case .sleepMac:
            await CommandPaletteSystemActions.sleepMac()
            closePalette()
        }
    }

    private var isMouseTriggeredActivation: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .leftMouseUp || event.type == .leftMouseDown || event.type == .rightMouseUp || event.type == .rightMouseDown
    }

    private func closePalette() {
        NotificationCenter.default.post(
            name: .endClipboardKeyboardNavigation,
            object: nil,
            userInfo: ["shouldCloseNotch": true]
        )
    }
}

import AppKit
import Defaults
import IOKit.pwr_mgt
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @ObservedObject private var appLauncher = AppLauncherManager.shared
    @ObservedObject private var preventSleepManager = PreventSleepManager.shared
    @State private var selectedRowID: String?
    @State private var pendingScrollRowID: String?
    @State private var pendingScrollAnchor: UnitPoint = .top

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

        return rows
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
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
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

    private func removeLastCharacter(from string: inout String) {
        guard !string.isEmpty else { return }
        string.removeLast()
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

    private func commandRows(for query: String) -> [CommandPaletteRootRow] {
        var rows: [ScoredCommandPaletteRow] = []

        if let calculatorResult = CalculatorEvaluator.evaluate(query), !query.isEmpty {
            rows.append(
                .init(
                    score: 20_000 + commandUsageBoost(for: "calculator.copy-result"),
                    row: CommandPaletteRootRow(
                        id: "calculator.\(calculatorResult.displayValue)",
                        title: calculatorResult.displayValue,
                        subtitle: "Copy result",
                        icon: "equal",
                        appItem: nil,
                        action: .copyToClipboard(calculatorResult.displayValue),
                        usageKey: "calculator.copy-result"
                    )
                )
            )
        }

        rows.append(contentsOf: preventSleepRows(for: query))

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

    private func preventSleepRows(for query: String) -> [ScoredCommandPaletteRow] {
        let stateSubtitle = preventSleepManager.statusText
        let aliases = ["prevent sleep", "awake", "caffeine", "caffeinate", "sleep", "insomnia"]
        let isRelevant = query.isEmpty || matches(query, aliases: aliases)
        guard isRelevant else { return [] }

        let rows: [ScoredCommandPaletteRow] = [
            .init(
                score: scoredCommandBase(query: query, aliases: aliases, baseScore: 9600, usageKey: "prevent-sleep.toggle", emptyScore: 8600),
                row: CommandPaletteRootRow(
                    id: "action.prevent-sleep.toggle",
                    title: preventSleepManager.isActive ? "Disable Prevent Sleep" : "Enable Prevent Sleep",
                    subtitle: stateSubtitle,
                    icon: preventSleepManager.isActive ? "poweroutlet.type.b.fill" : "poweroutlet.type.g.fill",
                    appItem: nil,
                    action: .togglePreventSleep,
                    usageKey: "prevent-sleep.toggle"
                )
            )
        ]

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
            proxy.scrollTo(selectedRowID)
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
        if let appItem = row.appItem {
            NSWorkspace.shared.openApplication(at: appItem.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error == nil {
                    Task { @MainActor in
                        appLauncher.recordLaunch(for: appItem)
                    }
                }
            }

            closePalette()
            return
        }

        guard let action = row.action else { return }

        if let usageKey = row.usageKey {
            CommandPaletteUsageManager.shared.recordUse(for: usageKey)
        }

        Task { @MainActor in
            await perform(action)
        }
    }

    @MainActor
    private func perform(_ action: CommandPaletteAction) async {
        switch action {
        case let .copyToClipboard(value):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            closePalette()
        case .togglePreventSleep:
            preventSleepManager.toggle()
            closePalette()
        case let .enablePreventSleep(duration):
            preventSleepManager.enable(for: duration)
            closePalette()
        }
    }

    private func closePalette() {
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
        panel.setClipboardKeyboardFocusEnabled(false)
    }
}

private struct CommandPaletteRootRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let appItem: AppLauncherItem?
    let action: CommandPaletteAction?
    let usageKey: String?

    init(id: String, title: String, subtitle: String?, icon: String?, appItem: AppLauncherItem? = nil, action: CommandPaletteAction? = nil, usageKey: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.appItem = appItem
        self.action = action
        self.usageKey = usageKey
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

private struct ScoredCommandPaletteRow {
    let score: Int
    let row: CommandPaletteRootRow
}

private struct CommandPaletteUsageStats: Codable {
    var useCount: Int = 0
    var lastUsedAt: Date?
}

@MainActor
private final class CommandPaletteUsageManager {
    static let shared = CommandPaletteUsageManager()

    private var statsByKey: [String: CommandPaletteUsageStats] = [:]

    private var storageURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("command-palette-usage.json")
    }

    private init() {
        load()
    }

    func recordUse(for usageKey: String) {
        var stats = statsByKey[usageKey] ?? .init()
        stats.useCount += 1
        stats.lastUsedAt = .now
        statsByKey[usageKey] = stats
        save()
    }

    func usageBoost(for usageKey: String) -> Int {
        guard let stats = statsByKey[usageKey] else { return 0 }

        let countBoost = min(stats.useCount * 18, 220)
        let recencyBoost: Int

        if let lastUsedAt = stats.lastUsedAt {
            let age = Date().timeIntervalSince(lastUsedAt)

            switch age {
            case ..<3600:
                recencyBoost = 320
            case ..<86400:
                recencyBoost = 240
            case ..<604_800:
                recencyBoost = 140
            case ..<2_592_000:
                recencyBoost = 60
            default:
                recencyBoost = 0
            }
        } else {
            recencyBoost = 0
        }

        return min(countBoost + recencyBoost, 420)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: CommandPaletteUsageStats].self, from: data) else { return }
        statsByKey = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statsByKey) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

private enum CommandPaletteAction {
    case copyToClipboard(String)
    case togglePreventSleep
    case enablePreventSleep(duration: TimeInterval)
}

@MainActor
final class PreventSleepManager: ObservableObject {
    static let shared = PreventSleepManager()

    @Published private(set) var isActive = false
    @Published private(set) var expiresAt: Date?

    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var expiryTask: Task<Void, Never>?

    private init() {
        restoreIfNeeded()
    }

    var statusText: String {
        guard isActive else { return "Currently off" }
        guard let expiresAt else { return "Currently on" }

        let remaining = max(0, expiresAt.timeIntervalSinceNow)
        return "On for \(durationLabel(for: remaining)) more"
    }

    func toggle() {
        isActive ? disable() : enable(for: nil)
    }

    func enable(for duration: TimeInterval?) {
        disableAssertions()
        createAssertions()

        let clampedDuration = duration.map { max(1, $0) }
        let nextExpiry = clampedDuration.map { Date().addingTimeInterval($0) }

        isActive = true
        expiresAt = nextExpiry
        persistState()
        scheduleExpiryIfNeeded()
    }

    func disable() {
        expiryTask?.cancel()
        expiryTask = nil
        disableAssertions()
        isActive = false
        expiresAt = nil
        persistState()
    }

    private func restoreIfNeeded() {
        guard Defaults[.preventSleepEnabled] else { return }

        let storedExpiry = Defaults[.preventSleepExpiresAt].flatMap { timestamp in
            timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }

        if let storedExpiry, storedExpiry <= .now {
            Defaults[.preventSleepEnabled] = false
            Defaults[.preventSleepExpiresAt] = nil
            return
        }

        let remainingDuration = storedExpiry.map { $0.timeIntervalSinceNow }
        enable(for: remainingDuration)
    }

    private func createAssertions() {
        let assertionName = "Notchera Prevent Sleep" as CFString
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), assertionName, &idleSleepAssertionID)
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), assertionName, &displaySleepAssertionID)
    }

    private func disableAssertions() {
        if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }

        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
    }

    private func scheduleExpiryIfNeeded() {
        expiryTask?.cancel()
        expiryTask = nil

        guard let expiresAt else { return }

        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = expiresAt.timeIntervalSinceNow
                if remaining <= 0 {
                    await MainActor.run {
                        self?.disable()
                    }
                    return
                }

                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    guard let self, self.isActive else { return }
                    self.objectWillChange.send()
                }
            }
        }
    }

    private func persistState() {
        Defaults[.preventSleepEnabled] = isActive
        Defaults[.preventSleepExpiresAt] = expiresAt?.timeIntervalSince1970
    }

    private func durationLabel(for duration: TimeInterval) -> String {
        let roundedDuration = max(60, Int(duration.rounded()))
        let hours = roundedDuration / 3600
        let minutes = (roundedDuration % 3600) / 60

        if roundedDuration >= 3600, minutes == 0 {
            return "\(hours)H"
        }

        if roundedDuration < 3600 {
            return "\(max(1, roundedDuration / 60))M"
        }

        return "\(hours)H \(minutes)M"
    }
}

private enum CalculatorEvaluator {
    static func evaluate(_ expression: String) -> CalculatorResult? {
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExpression.isEmpty else { return nil }
        guard shouldTreatAsCalculation(trimmedExpression) else { return nil }

        do {
            var parser = Parser(input: trimmedExpression)
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return CalculatorResult(value: value)
        } catch {
            return nil
        }
    }

    private static func shouldTreatAsCalculation(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.contains(where: { $0.isNumber }) else { return false }

        let operatorCount = characters.filter { "+-*/()%".contains($0) }.count
        if operatorCount > 0 {
            return true
        }

        if value.contains("(") || value.contains(")") {
            return true
        }

        let decimalSeparatorCount = characters.filter { $0 == "." }.count
        return decimalSeparatorCount == 1 && characters.allSatisfy { $0.isNumber || $0 == "." }
    }

    struct CalculatorResult {
        let value: Double

        var displayValue: String {
            if value.rounded(.towardZero) == value {
                return String(Int64(value))
            }

            return value.formatted(.number.precision(.fractionLength(0 ... 8)))
        }
    }

    private struct Parser {
        let input: [Character]
        var index = 0

        init(input: String) {
            self.input = Array(input.filter { !$0.isWhitespace })
        }

        mutating func parse() throws -> Double {
            guard !input.isEmpty else { throw ParserError.invalidExpression }
            let value = try parseExpression()
            guard index == input.count else { throw ParserError.invalidExpression }
            return value
        }

        private mutating func parseExpression() throws -> Double {
            var value = try parseTerm()

            while let token = currentToken {
                if token == "+" {
                    index += 1
                    value += try parseTerm()
                } else if token == "-" {
                    index += 1
                    value -= try parseTerm()
                } else {
                    break
                }
            }

            return value
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseFactor()

            while let token = currentToken {
                if token == "*" {
                    index += 1
                    value *= try parseFactor()
                } else if token == "/" {
                    index += 1
                    value /= try parseFactor()
                } else if token == "%" {
                    index += 1
                    value.formTruncatingRemainder(dividingBy: try parseFactor())
                } else {
                    break
                }
            }

            return value
        }

        private mutating func parseFactor() throws -> Double {
            guard let token = currentToken else { throw ParserError.invalidExpression }

            if token == "+" {
                index += 1
                return try parseFactor()
            }

            if token == "-" {
                index += 1
                return -(try parseFactor())
            }

            if token == "(" {
                index += 1
                let value = try parseExpression()
                guard currentToken == ")" else { throw ParserError.invalidExpression }
                index += 1
                return value
            }

            return try parseNumber()
        }

        private mutating func parseNumber() throws -> Double {
            let startIndex = index
            var hasDecimalPoint = false

            while let token = currentToken {
                if token.isNumber {
                    index += 1
                    continue
                }

                if token == ".", !hasDecimalPoint {
                    hasDecimalPoint = true
                    index += 1
                    continue
                }

                break
            }

            guard startIndex != index else { throw ParserError.invalidExpression }
            let stringValue = String(input[startIndex ..< index])
            guard let value = Double(stringValue) else { throw ParserError.invalidExpression }
            return value
        }

        private var currentToken: Character? {
            index < input.count ? input[index] : nil
        }
    }

    private enum ParserError: Error {
        case invalidExpression
    }
}

struct ClipboardResultsView: View {
    let isActive: Bool

    @ObservedObject private var clipboardHistoryManager = ClipboardHistoryManager.shared
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @Default(.clipboardHistoryRetention) private var retention
    @State private var hoveredItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollAnchor: UnitPoint = .top
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
            pendingScrollAnchor = .top
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
            proxy.scrollTo(hoveredItemID)
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

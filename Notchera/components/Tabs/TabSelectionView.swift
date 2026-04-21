import AppKit
import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

var tabs: [TabModel] {
    var items = [
        TabModel(label: "Music", icon: "music.note", view: .home),
        TabModel(label: "Calendar", icon: "calendar", view: .calendar),
        TabModel(label: "Command", icon: "magnifyingglass", view: .commandPalette),
        TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard),
        TabModel(label: "Shelf", icon: "folder.fill", view: .shelf)
    ]

    if Defaults[.enableAIUsage] {
        items.append(TabModel(label: "AI Usage", icon: "chart.bar.fill", view: .aiUsage))
    }

    return items
}

struct CalendarTabView: View {
    @ObservedObject private var calendarManager = CalendarManager.shared

    private let calendar = Calendar.current
    private let today = Date()
    private let jumpAmount = 7
    @State private var selectedDate = Date()
    @State private var hoveredDate: Date?
    @State private var isShowingSelectedDay = false
    @State private var isBackButtonHovered = false
    @State private var weekAnimationDirection: CGFloat = 0

    private var normalizedSelectedDate: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var minDate: Date {
        let anchor = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        return calendar.dateInterval(of: .month, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
    }

    private var maxDate: Date {
        let anchor = calendar.date(byAdding: .month, value: 3, to: today) ?? today
        let monthEnd = calendar.dateInterval(of: .month, for: anchor)?.end ?? anchor
        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthEnd) ?? anchor
        return calendar.startOfDay(for: lastDay)
    }

    private var visibleDates: [Date] {
        let weekday = calendar.component(.weekday, from: normalizedSelectedDate)
        let mondayOffset = (weekday + 5) % 7
        let unclampedStartDate = calendar.date(byAdding: .day, value: -mondayOffset, to: normalizedSelectedDate) ?? normalizedSelectedDate
        let latestStartDate = calendar.date(byAdding: .day, value: -6, to: maxDate) ?? maxDate
        let startDate = min(max(unclampedStartDate, minDate), latestStartDate)

        return (0 ..< 7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
                .map(calendar.startOfDay(for:))
        }
    }

    private var selectedEvents: [CalendarManager.CalendarEvent] {
        calendarManager.events(for: normalizedSelectedDate)
    }

    private var eventDates: Set<Date> {
        Set(calendarManager.eventsByDay.keys)
    }

    private var weeklyAnchorDate: Date {
        normalizedSelectedDate
    }

    private var currentDay: Date {
        calendar.startOfDay(for: today)
    }

    private var visibleMonthTitle: String {
        normalizedSelectedDate.formatted(.dateTime.month(.wide).day())
    }

    private var visibleMonthLabels: [String] {
        var labels: [String] = []

        for date in visibleDates {
            let label = date.formatted(.dateTime.month(.wide))
            if labels.last != label {
                labels.append(label)
            }
        }

        return labels
    }

    private var canGoBackward: Bool {
        weeklyAnchorDate > minDate
    }

    private var canGoForward: Bool {
        weeklyAnchorDate < maxDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isShowingSelectedDay {
                eventsSection
            } else {
                weekStrip
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            calendarManager.refreshAuthorizationState()
            calendarManager.loadEvents(around: today)
        }
        .onChange(of: calendarManager.authorizationState) { _, _ in
            calendarManager.loadEvents(around: today)
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                if isShowingSelectedDay {
                    Button {
                        withAnimation(.smooth) {
                            isShowingSelectedDay = false
                            selectedDate = weeklyAnchorDate
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isBackButtonHovered ? Color.white.opacity(0.9) : Color.secondary.opacity(0.88))
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isBackButtonHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isBackButtonHovered ? 1.02 : 1)
                    .animation(.easeOut(duration: 0.14), value: isBackButtonHovered)
                    .onHover { hovering in
                        isBackButtonHovered = hovering
                    }
                } else {
                    Color.clear
                        .frame(width: 24, height: 24)
                }

                Spacer(minLength: 0)
            }

            if isShowingSelectedDay {
                Text(visibleMonthTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            } else {
                ZStack {
                    monthHeaderLabels
                }
                .id(visibleMonthLabels.joined(separator: "|"))
                .transition(
                    .asymmetric(
                        insertion: .offset(x: weekAnimationDirection >= 0 ? 8 : -8).combined(with: .opacity),
                        removal: .offset(x: weekAnimationDirection >= 0 ? -8 : 8).combined(with: .opacity)
                    )
                )
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.94, blendDuration: 0), value: visibleMonthLabels)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var monthHeaderLabels: some View {
        HStack {
            if visibleMonthLabels.count > 1 {
                Text(visibleMonthLabels.first ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(visibleMonthLabels.last ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)
            } else {
                Spacer(minLength: 0)

                Text(visibleMonthLabels.first ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 12) {
            navigationButton(systemName: "chevron.left", disabled: !canGoBackward) {
                moveWeek(by: -jumpAmount)
            }

            HStack(spacing: 8) {
                ForEach(visibleDates, id: \.self) { date in
                    dayButton(for: date)
                }
            }
            .frame(maxWidth: .infinity)
            .id(visibleDates.map { $0.timeIntervalSinceReferenceDate }.map(Int.init).description)
            .transition(
                .asymmetric(
                    insertion: .offset(x: weekAnimationDirection >= 0 ? 20 : -20).combined(with: .opacity),
                    removal: .offset(x: weekAnimationDirection >= 0 ? -20 : 20).combined(with: .opacity)
                )
            )

            navigationButton(systemName: "chevron.right", disabled: !canGoForward) {
                moveWeek(by: jumpAmount)
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        switch calendarManager.authorizationState {
        case .authorized:
            if selectedEvents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.72))

                    Text("No events")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedEvents) { event in
                            eventRow(event)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 94, alignment: .top)
            }
        case .notDetermined:
            permissionRow(title: "Calendar access required", buttonTitle: "Allow access") {
                Task {
                    await calendarManager.requestAccess()
                }
            }
        case .denied, .restricted:
            permissionRow(title: "Calendar access denied", buttonTitle: "Open settings") {
                openCalendarSettings()
            }
        }
    }

    private func navigationButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private func dayButton(for date: Date) -> some View {
        let normalizedDate = calendar.startOfDay(for: date)
        let isCurrentDay = calendar.isDate(normalizedDate, inSameDayAs: currentDay)
        let hasEvents = eventDates.contains(normalizedDate)
        let isHovered = hoveredDate.map { calendar.isDate($0, inSameDayAs: normalizedDate) } ?? false
        let isHighlighted = isCurrentDay || isHovered
        let fillColor: Color = isCurrentDay
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.1)

        return Button {
            showSelectedDay(normalizedDate)
        } label: {
            VStack(spacing: 5) {
                Text(normalizedDate.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(normalizedDate.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .semibold))

                Circle()
                    .fill(hasEvents ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
                    .opacity(isCurrentDay && !hasEvents ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(isHighlighted ? AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) : AnyShape(Rectangle()))
        }
        .buttonStyle(.plain)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
            }
        }
        .scaleEffect(isHovered && !isCurrentDay ? 1.02 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            if hovering {
                hoveredDate = normalizedDate
                return
            }

            if hoveredDate.map({ calendar.isDate($0, inSameDayAs: normalizedDate) }) == true {
                hoveredDate = nil
            }
        }
    }

    private func eventRow(_ event: CalendarManager.CalendarEvent) -> some View {
        Button {
            openCalendar(for: event.startDate)
        } label: {
            HStack(spacing: 8) {
                Text(timeText(for: event))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        .constant(event.title),
                        font: .system(size: 13, weight: .semibold),
                        nsFont: .headline,
                        textColor: .white,
                        backgroundColor: .clear,
                        minDuration: 1.5,
                        frameWidth: 220
                    )

                    MarqueeText(
                        .constant(event.details),
                        font: .system(size: 11, weight: .medium),
                        nsFont: .subheadline,
                        textColor: Color.secondary,
                        backgroundColor: .clear,
                        minDuration: 1.5,
                        frameWidth: 220
                    )
                }

                Spacer(minLength: 0)
            }
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func permissionRow(title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(buttonTitle) {
                action()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func timeText(for event: CalendarManager.CalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }

        return event.startDate.formatted(date: .omitted, time: .shortened)
    }

    private func moveWeek(by value: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: value, to: weeklyAnchorDate) else {
            return
        }

        let normalizedDate = min(max(calendar.startOfDay(for: nextDate), minDate), maxDate)
        weekAnimationDirection = value >= 0 ? 1 : -1

        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0)) {
            selectedDate = normalizedDate
            hoveredDate = nil
        }
    }

    private func showSelectedDay(_ date: Date) {
        withAnimation(.smooth) {
            selectedDate = calendar.startOfDay(for: date)
            hoveredDate = nil
            isBackButtonHovered = false
            isShowingSelectedDay = true
        }
    }

    private func openCalendar(for date: Date) {
        let referenceDate = date.timeIntervalSinceReferenceDate
        guard let url = URL(string: "ical://com.apple.calendar/date?time=\(referenceDate)") ?? URL(string: "calshow:\(referenceDate)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openCalendarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preferences.users?Privacy_Calendars"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

struct ClipboardTabView: View {
    @ObservedObject private var clipboardHistoryManager = ClipboardHistoryManager.shared
    @ObservedObject private var coordinator = NotcheraViewCoordinator.shared
    @Default(.clipboardHistoryRetention) private var retention
    @State private var hoveredItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollItemID: ClipboardHistoryItem.ID?
    @State private var pendingScrollAnchor: UnitPoint = .center
    @State private var copiedItemID: ClipboardHistoryItem.ID?
    @State private var copyResetTask: Task<Void, Never>?
    @State private var query: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredItems: [ClipboardHistoryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return clipboardHistoryManager.items }

        return clipboardHistoryManager.items.filter { item in
            searchableText(for: item).contains(normalizedQuery)
        }
    }

    private var itemIDs: [ClipboardHistoryItem.ID] {
        filteredItems.map(\.id)
    }

    private var keyboardNavigationEnabled: Bool {
        coordinator.currentView == .clipboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                    .frame(width: 12)

                TextField("Search clipboard", text: $query)
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
                        LazyVStack(spacing: 6) {
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
                    .onChange(of: pendingScrollItemID) { _, _ in
                        scrollToHoveredItem(with: proxy)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.top, 0)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ClipboardKeyboardHandler(
                isEnabled: keyboardNavigationEnabled,
                onMoveUp: { moveSelection(by: -1) },
                onMoveDown: { moveSelection(by: 1) },
                onConfirm: { copyHoveredItem() },
                onCancel: { endKeyboardNavigation(shouldCloseNotch: true) }
            )
        }
        .background {
            NotchKeyboardFocusBridge(isEnabled: coordinator.currentView == .clipboard)
        }
        .onAppear {
            clipboardHistoryManager.pruneExpiredItems()
            pendingScrollAnchor = .center
            selectFirstItemIfNeeded()
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: retention) { _, _ in
            clipboardHistoryManager.pruneExpiredItems()
        }
        .onChange(of: coordinator.currentView) { _, newValue in
            guard newValue == .clipboard else { return }
            selectFirstItemIfNeeded(force: true)
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: query) { _, _ in
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
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private func searchableText(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case let .text(content):
            content.lowercased()
        case let .file(path):
            path.lowercased()
        }
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
        guard !filteredItems.isEmpty else {
            hoveredItemID = nil
            return
        }

        if force || hoveredItemID == nil {
            hoveredItemID = filteredItems.first?.id
        }
    }

    private func syncHoveredItem() {
        guard !filteredItems.isEmpty else {
            hoveredItemID = nil
            return
        }

        guard let hoveredItemID,
              filteredItems.contains(where: { $0.id == hoveredItemID })
        else {
            self.hoveredItemID = filteredItems.first?.id
            return
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }

        let items = filteredItems
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
              let item = filteredItems.first(where: { $0.id == hoveredItemID })
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

private struct NotchKeyboardFocusBridge: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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

    func updateNSView(_ nsView: KeyMonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ nsView: KeyMonitorHostView, coordinator: Coordinator) {
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
                guard let self, self.isEnabled else { return event }

                switch Int(event.keyCode) {
                case 125:
                    self.onMoveDown()
                    return nil
                case 126:
                    self.onMoveUp()
                    return nil
                case 36, 76:
                    self.onConfirm()
                    return nil
                case 53:
                    self.onCancel()
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

struct TabSelectionView: View {
    @ObservedObject var coordinator = NotcheraViewCoordinator.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
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

#Preview {
    NotcheraHeader().environmentObject(NotcheraViewModel())
}

import AppKit
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Music", icon: "music.note", view: .home),
    TabModel(label: "Calendar", icon: "calendar", view: .calendar),
    TabModel(label: "Shelf", icon: "folder.fill", view: .shelf)
]

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
        .padding(.horizontal, 16)
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
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
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
        let fillColor: Color = {
            if isCurrentDay {
                return Color.white.opacity(0.16)
            }

            if isHovered {
                return Color.white.opacity(0.1)
            }

            return Color.white.opacity(0.06)
        }()

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
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fillColor)
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

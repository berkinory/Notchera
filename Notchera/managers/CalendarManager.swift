import EventKit
import Foundation

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    enum AuthorizationState {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    struct CalendarEvent: Identifiable, Hashable {
        let id: String
        let title: String
        let details: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let calendarTitle: String
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined
    @Published private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]

    private let eventStore = EKEventStore()
    private let calendar = Calendar.current

    private init() {
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
        authorizationState = mapAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async {
        do {
            if #available(macOS 14.0, *) {
                _ = try await eventStore.requestFullAccessToEvents()
            } else {
                _ = try await eventStore.requestAccess(to: .event)
            }
        } catch {
            refreshAuthorizationState()
            return
        }

        refreshAuthorizationState()
    }

    func events(for date: Date) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }

    func loadEvents(around centerDate: Date, monthsBack: Int = 3, monthsForward: Int = 3) {
        guard authorizationState == .authorized else {
            eventsByDay = [:]
            return
        }

        let anchorDate = calendar.startOfDay(for: centerDate)
        let startDate = calendar.date(byAdding: .month, value: -monthsBack, to: anchorDate) ?? anchorDate
        let endDate = calendar.date(byAdding: .month, value: monthsForward + 1, to: anchorDate) ?? anchorDate
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title < rhs.title
                }

                return lhs.startDate < rhs.startDate
            }

        var grouped: [Date: [CalendarEvent]] = [:]

        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            grouped[day, default: []].append(
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? event.title! : "Untitled",
                    details: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? event.notes! : event.calendar.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title
                )
            )
        }

        eventsByDay = grouped
    }

    private func mapAuthorizationStatus(_ status: EKAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied, .writeOnly:
            return .denied
        case .authorized, .fullAccess:
            return .authorized
        @unknown default:
            return .denied
        }
    }
}

@testable import AppleBridge
import EventKit

extension MockEventKitStore {
    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]) -> NSPredicate {
        lastEventQuery = EventQuery(start: startDate, end: endDate, calendars: calendars)
        return NSPredicate(value: true)
    }

    func fetchEvents(matching predicate: NSPredicate) throws -> [EKEvent] {
        _ = predicate
        guard let lastEventQuery else {
            return events
        }

        let calendarIDs = Set(lastEventQuery.calendars.map(\.calendarIdentifier))
        return events.filter { event in
            guard let calendarID = event.calendar?.calendarIdentifier, calendarIDs.contains(calendarID) else {
                return false
            }
            return event.endDate >= lastEventQuery.start && event.startDate <= lastEventQuery.end
        }
    }

    func fetchEvent(withIdentifier id: String) throws -> EKEvent? {
        events.first { event in
            if event.eventIdentifier == id {
                return true
            }
            return Self.syntheticEventIdentifier(for: event) == id
        }
    }

    static func syntheticEventIdentifier(for event: EKEvent) -> String {
        "evt-\(event.calendarItemIdentifier)"
    }

    func makeEvent() -> EKEvent {
        EKEvent(eventStore: eventStore)
    }

    func saveEvent(_ event: EKEvent, commit: Bool) throws {
        guard commit else { return }

        let existingID = event.calendarItemIdentifier
        if existingID.isEmpty {
            event.setValue("mock-evt-\(nextEventID)", forKey: "calendarItemIdentifier")
            nextEventID += 1
        }

        if let index = events.firstIndex(where: { $0.calendarItemIdentifier == event.calendarItemIdentifier }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }

    func removeEvent(_ event: EKEvent, commit: Bool) throws {
        guard commit else { return }
        events.removeAll { $0.calendarItemIdentifier == event.calendarItemIdentifier }
    }

    func makeTestEventCalendar(calendarIdentifier: String, title: String = "Test Calendar") -> EKCalendar {
        EventKitTestSupport.makeEventCalendar(
            eventStore: eventStore,
            calendarIdentifier: calendarIdentifier,
            title: title
        )
    }

    func makeTestEvent(
        calendarItemIdentifier: String,
        calendarIdentifier: String? = nil,
        title: String? = nil,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endDate: Date = Date(timeIntervalSince1970: 1_700_003_600)
    ) -> EKEvent {
        EventKitTestSupport.makeEvent(
            eventStore: eventStore,
            calendarItemIdentifier: calendarItemIdentifier,
            calendarIdentifier: calendarIdentifier,
            title: title,
            startDate: startDate,
            endDate: endDate
        )
    }
}

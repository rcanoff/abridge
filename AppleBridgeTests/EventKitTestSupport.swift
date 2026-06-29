@testable import AppleBridge
import EventKit
import Foundation

@MainActor
enum EventKitTestSupport {
    static func makeReminder(
        calendarItemIdentifier: String,
        calendarIdentifier: String? = nil,
        title: String? = nil,
        isCompleted: Bool = false,
        notes: String? = nil
    ) -> EKReminder {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.setValue(calendarItemIdentifier, forKey: "calendarItemIdentifier")

        if let title {
            reminder.title = title
        }
        if isCompleted {
            reminder.completionDate = Date()
            reminder.setValue(true, forKey: "completed")
        } else {
            reminder.completionDate = nil
            reminder.setValue(false, forKey: "completed")
        }
        reminder.notes = notes

        if let calendarIdentifier {
            let calendar = makeCalendar(
                eventStore: eventStore,
                calendarIdentifier: calendarIdentifier,
                title: "Test List"
            )
            reminder.calendar = calendar
        }

        return reminder
    }

    static func makeCalendar(
        eventStore: EKEventStore = EKEventStore(),
        calendarIdentifier: String,
        title: String = "Test List"
    ) -> EKCalendar {
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.setValue(calendarIdentifier, forKey: "calendarIdentifier")
        calendar.title = title
        calendar.source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first
        return calendar
    }

    static func makeEventCalendar(
        eventStore: EKEventStore = EKEventStore(),
        calendarIdentifier: String,
        title: String = "Test Calendar"
    ) -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.setValue(calendarIdentifier, forKey: "calendarIdentifier")
        calendar.title = title
        calendar.source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first
        return calendar
    }

    static func makeEvent(
        eventStore: EKEventStore = EKEventStore(),
        calendarItemIdentifier: String,
        calendarIdentifier: String? = nil,
        title: String? = nil,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endDate: Date = Date(timeIntervalSince1970: 1_700_003_600)
    ) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.setValue(calendarItemIdentifier, forKey: "calendarItemIdentifier")
        if let title {
            event.title = title
        }
        event.startDate = startDate
        event.endDate = endDate

        if let calendarIdentifier {
            event.calendar = makeEventCalendar(
                eventStore: eventStore,
                calendarIdentifier: calendarIdentifier
            )
        }

        return event
    }
}

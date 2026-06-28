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
        reminder.isCompleted = isCompleted
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
}

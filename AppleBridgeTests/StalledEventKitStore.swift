@testable import AppleBridge
import EventKit
import Foundation

/// Simulates EventKit's async reminder fetch never invoking its completion handler.
@MainActor
final class StalledEventKitStore: EventKitStoreing {
    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var eventAuthorizationStatusValue: EKAuthorizationStatus = .fullAccess
    var calendars: [EKCalendar] = []
    var eventCalendarsList: [EKCalendar] = []
    var fetchTimeout: TimeInterval = 0.05

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        authorizationStatus
    }

    func eventAuthorizationStatus() -> EKAuthorizationStatus {
        eventAuthorizationStatusValue
    }

    func reminderCalendars() -> [EKCalendar] {
        calendars
    }

    func eventCalendars() -> [EKCalendar] {
        eventCalendarsList
    }

    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate {
        _ = calendars
        return NSPredicate(value: true)
    }

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        _ = startDate
        _ = endDate
        _ = calendars
        return NSPredicate(value: true)
    }

    func predicateForCompletedReminders(
        withCompletionDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        _ = startDate
        _ = endDate
        _ = calendars
        return NSPredicate(value: true)
    }

    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
        _ = predicate
        try EventKitReminderFetch.waitForCompletion(timeout: fetchTimeout) { _ in
            // Intentionally never call complete — mirrors a stalled EventKit callback.
        }
        return []
    }

    func fetchReminder(withIdentifier id: String) throws -> EKReminder? {
        _ = id
        return nil
    }

    func makeReminder() -> EKReminder {
        EKReminder(eventStore: EKEventStore())
    }

    func saveReminder(_ reminder: EKReminder, commit: Bool) throws {
        _ = reminder
        _ = commit
    }

    func removeReminder(_ reminder: EKReminder, commit: Bool) throws {
        _ = reminder
        _ = commit
    }

    func sources() -> [EKSource] {
        [Self.stubReminderSource]
    }

    func defaultReminderSource() -> EKSource? {
        Self.stubReminderSource
    }

    func defaultEventSource() -> EKSource? {
        Self.stubReminderSource
    }

    func makeReminderCalendar() -> EKCalendar {
        EKCalendar(for: .reminder, eventStore: EKEventStore())
    }

    func makeEventCalendar() -> EKCalendar {
        EKCalendar(for: .event, eventStore: EKEventStore())
    }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        _ = calendar
        _ = commit
    }

    func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        _ = calendar
        _ = commit
    }

    private static let stubReminderSource: EKSource = {
        let source = EKSource()
        source.setValue("mock-source-local", forKey: "sourceIdentifier")
        source.setValue("Local", forKey: "title")
        return source
    }()
}

@testable import AppleBridge
import EventKit
import Foundation

@MainActor
final class MockEventKitStore: EventKitStoreing {
    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var calendars: [EKCalendar] = []
    var fakeReminders: [FakeReminder] = []

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        authorizationStatus
    }

    func reminderCalendars() -> [EKCalendar] {
        calendars
    }

    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate {
        _ = calendars
        return NSPredicate(value: true)
    }

    func fetchReminders(matching predicate: NSPredicate) throws -> [any ReminderRepresentable] {
        _ = predicate
        return fakeReminders
    }

    func fetchReminder(withIdentifier id: String) throws -> (any ReminderRepresentable)? {
        fakeReminders.first { $0.calendarItemIdentifier == id }
    }
}

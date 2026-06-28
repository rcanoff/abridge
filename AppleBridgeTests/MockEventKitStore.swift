@testable import AppleBridge
import EventKit
import Foundation

@MainActor
final class MockEventKitStore: EventKitStoreing {
    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var calendars: [EKCalendar] = []
    var reminders: [EKReminder] = []

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

    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
        _ = predicate
        return reminders
    }
}

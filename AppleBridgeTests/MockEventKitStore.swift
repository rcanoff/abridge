import EventKit
import Foundation
@testable import AppleBridge

final class MockEventKitStore: EventKitStoreing, @unchecked Sendable {
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
        NSPredicate(value: true)
    }

    func fetchReminders(matching predicate: NSPredicate) -> [EKReminder] {
        _ = predicate
        return reminders
    }
}
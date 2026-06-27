import EventKit
import Foundation
@testable import AppleBridge

/// Simulates EventKit's async reminder fetch never invoking its completion handler.
@MainActor
final class StalledEventKitStore: EventKitStoreing, Sendable {
    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var calendars: [EKCalendar] = []
    var fetchTimeout: TimeInterval = 0.05

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
        try EventKitReminderFetch.waitForCompletion(timeout: fetchTimeout) { _ in
            // Intentionally never call complete — mirrors a stalled EventKit callback.
        }
        return []
    }
}
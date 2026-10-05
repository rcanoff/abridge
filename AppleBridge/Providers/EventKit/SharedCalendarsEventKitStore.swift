@preconcurrency import EventKit
import Foundation

extension EventKitStoreing {
    func calendars(for kind: CalendarSharingKind) -> [EKCalendar] {
        switch kind {
        case .reminderLists: reminderCalendars()
        case .eventCalendars: eventCalendars()
        }
    }
}

/// Limits MCP to the calendars the user shares in Settings. Calendars outside the selection are
/// absent from calendar lists, and their reminders and events read as unknown identifiers.
@MainActor
final class SharedCalendarsEventKitStore: EventKitStoreing {
    private let base: any EventKitStoreing
    private let sharing: CalendarSharingStore

    init(base: any EventKitStoreing, sharing: CalendarSharingStore) {
        self.base = base
        self.sharing = sharing
    }

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        base.reminderAuthorizationStatus()
    }

    func eventAuthorizationStatus() -> EKAuthorizationStatus {
        base.eventAuthorizationStatus()
    }

    func reminderCalendars() -> [EKCalendar] {
        base.reminderCalendars().filter { sharing.isShared($0, for: .reminderLists) }
    }

    func eventCalendars() -> [EKCalendar] {
        base.eventCalendars().filter { sharing.isShared($0, for: .eventCalendars) }
    }

    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate {
        base.predicateForReminders(in: calendars)
    }

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        base.predicateForIncompleteReminders(withDueDateStarting: startDate, ending: endDate, calendars: calendars)
    }

    func predicateForCompletedReminders(
        withCompletionDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        base.predicateForCompletedReminders(
            withCompletionDateStarting: startDate,
            ending: endDate,
            calendars: calendars
        )
    }

    /// Filters results too: an empty shared selection yields an empty calendar array, which
    /// EventKit predicates do not reliably treat as "no calendars".
    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
        try base.fetchReminders(matching: predicate).filter { sharing.isShared($0.calendar, for: .reminderLists) }
    }

    func fetchReminder(withIdentifier id: String) throws -> EKReminder? {
        guard let reminder = try base.fetchReminder(withIdentifier: id),
              sharing.isShared(reminder.calendar, for: .reminderLists)
        else {
            return nil
        }
        return reminder
    }

    func makeReminder() -> EKReminder {
        base.makeReminder()
    }

    func saveReminder(_ reminder: EKReminder, commit: Bool) throws {
        try base.saveReminder(reminder, commit: commit)
    }

    func removeReminder(_ reminder: EKReminder, commit: Bool) throws {
        try base.removeReminder(reminder, commit: commit)
    }

    func sources() -> [EKSource] {
        base.sources()
    }

    func defaultReminderSource() -> EKSource? {
        base.defaultReminderSource()
    }

    func defaultEventSource() -> EKSource? {
        base.defaultEventSource()
    }

    func makeReminderCalendar() -> EKCalendar {
        base.makeReminderCalendar()
    }

    func makeEventCalendar() -> EKCalendar {
        base.makeEventCalendar()
    }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        let kind: CalendarSharingKind = calendar.allowedEntityTypes
            .contains(.reminder) ? .reminderLists : .eventCalendars
        let isNew = !base.calendars(for: kind).contains { $0.calendarIdentifier == calendar.calendarIdentifier }
        try base.saveCalendar(calendar, commit: commit)
        if isNew {
            sharing.shareCreatedCalendar(identifier: calendar.calendarIdentifier, for: kind)
        }
    }

    func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        try base.removeCalendar(calendar, commit: commit)
    }

    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]) -> NSPredicate {
        base.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
    }

    func fetchEvents(matching predicate: NSPredicate) throws -> [EKEvent] {
        try base.fetchEvents(matching: predicate).filter { sharing.isShared($0.calendar, for: .eventCalendars) }
    }

    func fetchEvent(withIdentifier id: String) throws -> EKEvent? {
        guard let event = try base.fetchEvent(withIdentifier: id),
              sharing.isShared(event.calendar, for: .eventCalendars)
        else {
            return nil
        }
        return event
    }

    func makeEvent() -> EKEvent {
        base.makeEvent()
    }

    func saveEvent(_ event: EKEvent, commit: Bool) throws {
        try base.saveEvent(event, commit: commit)
    }

    func removeEvent(_ event: EKEvent, commit: Bool) throws {
        try base.removeEvent(event, commit: commit)
    }

    func canRespondToInvitation(for event: EKEvent) -> Bool {
        base.canRespondToInvitation(for: event)
    }

    func acceptEventInvitation(_ event: EKEvent) throws {
        try base.acceptEventInvitation(event)
    }

    func declineEventInvitation(_ event: EKEvent) throws {
        try base.declineEventInvitation(event)
    }

    func tentativeEventInvitation(_ event: EKEvent) throws {
        try base.tentativeEventInvitation(event)
    }

    func eventIdentifier(for event: EKEvent) -> String? {
        base.eventIdentifier(for: event)
    }
}

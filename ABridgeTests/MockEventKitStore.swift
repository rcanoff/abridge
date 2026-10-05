@testable import ABridge
import EventKit
import Foundation

@MainActor
final class MockEventKitStore: EventKitStoreing {
    let eventStore = EKEventStore()

    private var nextReminderID = 1
    private var nextCalendarID = 1
    var nextEventID = 1
    private lazy var stubReminderSource: EKSource = Self.makeStubReminderSource()

    enum PredicateKind: Equatable {
        case all(calendars: [EKCalendar])
        case incomplete(start: Date?, end: Date?, calendars: [EKCalendar])
        case completed(start: Date?, end: Date?, calendars: [EKCalendar])
    }

    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var eventAuthorizationStatusValue: EKAuthorizationStatus = .fullAccess
    var calendars: [EKCalendar] = []
    var eventCalendarsList: [EKCalendar] = []
    var events: [EKEvent] = []
    var reminders: [EKReminder] = []
    var invitationRespondableEventIDs: Set<String> = []
    var acceptedInvitationEventIDs: Set<String> = []
    var declinedInvitationEventIDs: Set<String> = []
    var tentativeInvitationEventIDs: Set<String> = []
    var lastPredicateKind: PredicateKind?
    struct EventQuery: Equatable {
        let start: Date
        let end: Date
        let calendars: [EKCalendar]
    }

    var lastEventQuery: EventQuery?

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
        lastPredicateKind = .all(calendars: calendars)
        return NSPredicate(value: true)
    }

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        lastPredicateKind = .incomplete(start: startDate, end: endDate, calendars: calendars)
        return NSPredicate(value: true)
    }

    func predicateForCompletedReminders(
        withCompletionDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        lastPredicateKind = .completed(start: startDate, end: endDate, calendars: calendars)
        return NSPredicate(value: true)
    }

    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
        _ = predicate
        guard let lastPredicateKind else {
            return reminders
        }

        let calendarIDs = calendarIdentifiers(for: lastPredicateKind)
        return reminders.filter { reminder in
            matchesPredicate(reminder, kind: lastPredicateKind, calendarIDs: calendarIDs)
        }
    }

    private func matchesPredicate(
        _ reminder: EKReminder,
        kind: PredicateKind,
        calendarIDs: Set<String>
    ) -> Bool {
        if !calendarIDs.isEmpty {
            guard let calendarID = reminder.calendar?.calendarIdentifier,
                  calendarIDs.contains(calendarID)
            else {
                return false
            }
        }

        switch kind {
        case .all:
            return true
        case let .incomplete(start, end, _):
            guard !isReminderCompleted(reminder) else {
                return false
            }
            return matchesDueDateRange(reminder: reminder, start: start, end: end)
        case let .completed(start, end, _):
            return matchesCompletedReminder(reminder, start: start, end: end)
        }
    }

    private func matchesCompletedReminder(_ reminder: EKReminder, start: Date?, end: Date?) -> Bool {
        guard isReminderCompleted(reminder) else {
            return false
        }
        guard start != nil || end != nil else {
            return true
        }
        guard let completionDate = reminder.completionDate else {
            return false
        }
        if let start, completionDate < start {
            return false
        }
        if let end, completionDate > end {
            return false
        }
        return true
    }

    func fetchReminder(withIdentifier id: String) throws -> EKReminder? {
        reminders.first { $0.calendarItemIdentifier == id }
    }

    func makeReminder() -> EKReminder {
        EKReminder(eventStore: eventStore)
    }

    func saveReminder(_ reminder: EKReminder, commit: Bool) throws {
        guard commit else { return }

        // Mirror EventKit: repeating reminders require dueDateComponents with a date.
        let hasRecurrence = !(reminder.recurrenceRules ?? []).isEmpty
        let due = reminder.dueDateComponents
        let hasDueDate = due != nil && (due?.year != nil || due?.month != nil || due?.day != nil)
        if hasRecurrence, !hasDueDate {
            throw NSError(
                domain: "EKErrorDomain",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "A repeating reminder must have a due date."]
            )
        }

        // Mirror EventKit: completing a recurring reminder advances the series — only the
        // next incomplete occurrence remains obtainable (isCompleted false, due advances).
        if hasRecurrence, reminder.isCompleted {
            reminder.isCompleted = false
            reminder.completionDate = nil
            if var components = reminder.dueDateComponents,
               let current = Calendar.current.date(from: components),
               let rule = reminder.recurrenceRules?.first
            {
                let next = Self.nextOccurrenceDate(after: current, rule: rule) ?? current
                components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: next
                )
                reminder.dueDateComponents = components
            }
        } else if reminder.isCompleted, reminder.completionDate == nil {
            // EventKit sets completionDate when isCompleted becomes true.
            reminder.completionDate = Date()
        } else if !reminder.isCompleted {
            reminder.completionDate = nil
        }

        let existingID = reminder.calendarItemIdentifier
        if existingID.isEmpty {
            reminder.setValue("mock-rem-\(nextReminderID)", forKey: "calendarItemIdentifier")
            nextReminderID += 1
        }

        if let index = reminders.firstIndex(where: { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }) {
            reminders[index] = reminder
        } else {
            reminders.append(reminder)
        }
    }

    func removeReminder(_ reminder: EKReminder, commit: Bool) throws {
        guard commit else { return }
        reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
    }

    func sources() -> [EKSource] {
        let liveSources = eventStore.sources
        return liveSources.isEmpty ? [stubReminderSource] : liveSources
    }

    func defaultReminderSource() -> EKSource? {
        eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first
            ?? stubReminderSource
    }

    func defaultEventSource() -> EKSource? {
        eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first
            ?? stubReminderSource
    }

    func makeReminderCalendar() -> EKCalendar {
        EKCalendar(for: .reminder, eventStore: eventStore)
    }

    func makeEventCalendar() -> EKCalendar {
        EKCalendar(for: .event, eventStore: eventStore)
    }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        guard commit else { return }

        let existingID = calendar.calendarIdentifier
        if existingID.isEmpty {
            calendar.setValue("mock-cal-\(nextCalendarID)", forKey: "calendarIdentifier")
            nextCalendarID += 1
        }

        if calendar.source == nil {
            calendar.source = isEventCalendar(calendar) ? defaultEventSource() : defaultReminderSource()
        }

        var storage = isEventCalendar(calendar) ? eventCalendarsList : calendars
        if let index = storage.firstIndex(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
            storage[index] = calendar
        } else {
            storage.append(calendar)
        }
        if isEventCalendar(calendar) {
            eventCalendarsList = storage
        } else {
            calendars = storage
        }
    }

    func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        guard commit else { return }
        if isEventCalendar(calendar) {
            eventCalendarsList.removeAll { $0.calendarIdentifier == calendar.calendarIdentifier }
        } else {
            calendars.removeAll { $0.calendarIdentifier == calendar.calendarIdentifier }
        }
    }

    private func isEventCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.allowedEntityTypes.contains(.event) && !calendar.allowedEntityTypes.contains(.reminder)
    }

    /// Advances due date by the rule's frequency and interval (test double for series advance).
    private static func nextOccurrenceDate(after current: Date, rule: EKRecurrenceRule) -> Date? {
        let interval = max(rule.interval, 1)
        let component: Calendar.Component = switch rule.frequency {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        @unknown default: .day
        }
        return Calendar.current.date(byAdding: component, value: interval, to: current)
    }

    func makeTestCalendar(calendarIdentifier: String, title: String = "Test List") -> EKCalendar {
        EventKitTestSupport.makeCalendar(
            eventStore: eventStore,
            calendarIdentifier: calendarIdentifier,
            title: title
        )
    }

    private func calendarIdentifiers(for kind: PredicateKind) -> Set<String> {
        let calendars: [EKCalendar] = switch kind {
        case let .all(cals):
            cals
        case let .incomplete(_, _, cals), let .completed(_, _, cals):
            cals
        }
        return Set(calendars.map(\.calendarIdentifier))
    }

    private func matchesDueDateRange(reminder: EKReminder, start: Date?, end: Date?) -> Bool {
        guard start != nil || end != nil else {
            return true
        }
        guard let dueDate = dueDate(from: reminder.dueDateComponents) else {
            return false
        }
        if let start, dueDate < start {
            return false
        }
        if let end, dueDate > end {
            return false
        }
        return true
    }

    private func isReminderCompleted(_ reminder: EKReminder) -> Bool {
        reminder.isCompleted || reminder.completionDate != nil
    }

    private func dueDate(from components: DateComponents?) -> Date? {
        guard let components else {
            return nil
        }
        return Calendar.current.date(from: components)
    }

    private static func makeStubReminderSource() -> EKSource {
        let source = EKSource()
        source.setValue("mock-source-local", forKey: "sourceIdentifier")
        source.setValue("Local", forKey: "title")
        return source
    }
}

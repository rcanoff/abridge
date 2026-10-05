@preconcurrency import EventKit
import Foundation

@MainActor
final class LiveEventKitStore: EventKitStoreing {
    private let makeEventStore: @MainActor () -> EKEventStore
    private let reminderAuthorization: @MainActor () -> EKAuthorizationStatus
    private let eventAuthorization: @MainActor () -> EKAuthorizationStatus
    private var storedEventStore: EKEventStore
    private var lastReminderAuthorization: EKAuthorizationStatus
    private var lastEventAuthorization: EKAuthorizationStatus

    /// EventKit requires a new `EKEventStore` after the user grants access; a store created while
    /// unauthorized keeps an empty calendar list until process restart.
    init(
        makeEventStore: @escaping @MainActor () -> EKEventStore = { EKEventStore() },
        reminderAuthorizationStatus: @escaping @MainActor () -> EKAuthorizationStatus = {
            EKEventStore.authorizationStatus(for: .reminder)
        },
        eventAuthorizationStatus: @escaping @MainActor () -> EKAuthorizationStatus = {
            EKEventStore.authorizationStatus(for: .event)
        }
    ) {
        self.makeEventStore = makeEventStore
        reminderAuthorization = reminderAuthorizationStatus
        eventAuthorization = eventAuthorizationStatus
        storedEventStore = makeEventStore()
        lastReminderAuthorization = reminderAuthorizationStatus()
        lastEventAuthorization = eventAuthorizationStatus()
    }

    convenience init(eventStore: EKEventStore) {
        self.init(makeEventStore: { eventStore })
    }

    private var eventStore: EKEventStore {
        let reminder = reminderAuthorization()
        let event = eventAuthorization()
        if reminder != lastReminderAuthorization || event != lastEventAuthorization {
            storedEventStore = makeEventStore()
            lastReminderAuthorization = reminder
            lastEventAuthorization = event
        }
        return storedEventStore
    }

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        reminderAuthorization()
    }

    func eventAuthorizationStatus() -> EKAuthorizationStatus {
        eventAuthorization()
    }

    func reminderCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .reminder)
    }

    func eventCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate {
        eventStore.predicateForReminders(in: calendars)
    }

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startDate,
            ending: endDate,
            calendars: calendars
        )
    }

    func predicateForCompletedReminders(
        withCompletionDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: startDate,
            ending: endDate,
            calendars: calendars
        )
    }

    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder] {
        var fetched: [EKReminder] = []
        try EventKitReminderFetch.waitForCompletion { complete in
            eventStore.fetchReminders(matching: predicate) { reminders in
                fetched = reminders ?? []
                complete()
            }
        }
        return fetched
    }

    func fetchReminder(withIdentifier id: String) throws -> EKReminder? {
        guard let item = eventStore.calendarItem(withIdentifier: id) else {
            return nil
        }
        guard let reminder = item as? EKReminder else {
            throw EventKitProviderError.invalidArguments("Not a reminder: \(id)")
        }
        return reminder
    }

    func makeReminder() -> EKReminder {
        EKReminder(eventStore: eventStore)
    }

    func saveReminder(_ reminder: EKReminder, commit: Bool) throws {
        try eventStore.save(reminder, commit: commit)
    }

    func removeReminder(_ reminder: EKReminder, commit: Bool) throws {
        try eventStore.remove(reminder, commit: commit)
    }

    func sources() -> [EKSource] {
        eventStore.sources
    }

    func defaultReminderSource() -> EKSource? {
        eventStore.defaultCalendarForNewReminders()?.source ?? eventStore.sources.first
    }

    func defaultEventSource() -> EKSource? {
        eventStore.defaultCalendarForNewEvents?.source ?? eventStore.sources.first
    }

    func makeReminderCalendar() -> EKCalendar {
        EKCalendar(for: .reminder, eventStore: eventStore)
    }

    func makeEventCalendar() -> EKCalendar {
        EKCalendar(for: .event, eventStore: eventStore)
    }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        try eventStore.saveCalendar(calendar, commit: commit)
    }

    func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        try eventStore.removeCalendar(calendar, commit: commit)
    }

    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]) -> NSPredicate {
        eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
    }

    func fetchEvents(matching predicate: NSPredicate) throws -> [EKEvent] {
        eventStore.events(matching: predicate)
    }

    func fetchEvent(withIdentifier id: String) throws -> EKEvent? {
        eventStore.event(withIdentifier: id)
    }

    func makeEvent() -> EKEvent {
        EKEvent(eventStore: eventStore)
    }

    func saveEvent(_ event: EKEvent, commit: Bool) throws {
        try eventStore.save(event, span: .thisEvent, commit: commit)
    }

    func removeEvent(_ event: EKEvent, commit: Bool) throws {
        try eventStore.remove(event, span: .thisEvent, commit: commit)
    }
}

@MainActor
enum LiveEventKitEnvironment {
    private static let eventKitStore = LiveEventKitStore()
    /// Shared with the Permissions UI so the calendar picker and MCP tools read the same selection.
    static let calendarSharingStore = CalendarSharingStore { eventKitStore.calendars(for: $0) }
    static let sharedProvider = EventKitProvider(
        store: SharedCalendarsEventKitStore(base: eventKitStore, sharing: calendarSharingStore)
    )
}

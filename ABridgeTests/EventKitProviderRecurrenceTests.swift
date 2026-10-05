@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderRecurrence")
struct EventKitProviderRecurrenceTests {
    @Test
    @MainActor
    func setReminderRecurrenceReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-recurrence")]
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-recurrence-1",
            calendarIdentifier: "list-recurrence",
            title: "Recurring task",
            notes: "unchanged"
        )
        reminder.dueDateComponents = DateComponents(year: 2026, month: 7, day: 15, hour: 9, minute: 0)
        mockStore.reminders = [reminder]
        let provider = EventKitProvider(store: mockStore)

        let payload =
            #"{"calendar_item_identifier":"rem-recurrence-1","recurrence_rules":[{"frequency":"daily","interval":2}]}"#
        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: payload
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Recurring task"))
        #expect(response.payloadJson.contains("unchanged"))
        #expect(response.payloadJson.contains("frequency"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].recurrenceRules?.count == 1)
        #expect(mockStore.reminders[0].recurrenceRules?.first?.frequency == .daily)
        #expect(mockStore.reminders[0].recurrenceRules?.first?.interval == 2)
    }

    @Test
    @MainActor
    func setReminderRecurrenceEmptyArrayClearsRecurrenceRules() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-clear-recurrence")]
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-clear-recurrence-1",
            calendarIdentifier: "list-clear-recurrence",
            title: "Clear recurrence"
        )
        reminder.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        mockStore.reminders = [reminder]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-clear-recurrence-1","recurrence_rules":[]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Clear recurrence"))
        #expect(mockStore.reminders.count == 1)
        #expect((mockStore.reminders[0].recurrenceRules ?? []).isEmpty)
    }

    @Test
    @MainActor
    func setReminderRecurrenceWithoutDueDateSurfacesEventKitConstraint() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-no-due")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-no-due",
                calendarIdentifier: "list-no-due",
                title: "No due date"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-no-due","recurrence_rules":[{"frequency":"weekly"}]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("A repeating reminder must have a due date.") == true)
        // Must not invent dueDateComponents to make save succeed
        let due = mockStore.reminders[0].dueDateComponents
        #expect(due == nil || (due?.year == nil && due?.month == nil && due?.day == nil))
    }

    @Test
    @MainActor
    func setReminderRecurrenceUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"missing","recurrence_rules":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrencePermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-1","recurrence_rules":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

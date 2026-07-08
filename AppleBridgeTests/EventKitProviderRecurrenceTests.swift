@testable import AppleBridge
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
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-recurrence-1",
                calendarIdentifier: "list-recurrence",
                title: "Recurring task",
                notes: "unchanged"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-recurrence-1","recurrence_rules":[{"frequency":"daily","interval":2}]}"#
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
    func setReminderRecurrenceMissingReminderIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"recurrence_rules":[{"frequency":"daily"}]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier is required") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrenceMissingRecurrenceRulesReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("recurrence_rules is required") == true)
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

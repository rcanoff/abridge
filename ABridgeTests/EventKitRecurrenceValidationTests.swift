@testable import ABridge
import Foundation
import Testing

@Suite("EventKitRecurrenceValidation")
struct EventKitRecurrenceValidationTests {
    @MainActor
    private func providerWithReminder(reminderID: String = "rem-rec-val") -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-rec-val")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: reminderID,
                calendarIdentifier: "list-rec-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func setReminderRecurrenceRejectsInvalidRecurrenceFrequency() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: """
            {"calendar_item_identifier":"rem-rec-val","recurrence_rules":[{"frequency":"hourly"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Invalid recurrence frequency") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrenceNullRulesMapsToEmptyWithoutPureSchemaDualValidation() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"rem-rec-val","recurrence_rules":null}"#
        )

        #expect(response.errorJson?.contains("recurrence_rules must be an array") != true)
        #expect(response.ok == true)
    }
}

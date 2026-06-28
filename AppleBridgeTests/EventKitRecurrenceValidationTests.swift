@testable import AppleBridge
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
    func setReminderRecurrenceRejectsEmptyReminderID() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"reminder_id":"   ","recurrence_rules":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("reminder_id must not be empty") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrenceRejectsInvalidRecurrenceFrequency() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: """
            {"reminder_id":"rem-rec-val","recurrence_rules":[{"frequency":"hourly"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Invalid recurrence frequency") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrenceRejectsNullRecurrenceRules() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"reminder_id":"rem-rec-val","recurrence_rules":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("recurrence_rules must be an array") == true)
    }
}

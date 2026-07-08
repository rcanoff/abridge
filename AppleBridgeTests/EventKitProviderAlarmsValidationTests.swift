@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderAlarmsValidation")
struct EventKitProviderAlarmsValidationTests {
    @MainActor
    private func providerWithReminder(reminderID: String = "rem-val") -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-val")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: reminderID,
                calendarIdentifier: "list-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func setReminderAlarmsRejectsEmptyReminderID() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"   ","alarms":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier must not be empty") == true)
    }

    @Test
    @MainActor
    func setReminderAlarmsRejectsInvalidAlarmRelativeOffset() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: """
            {"calendar_item_identifier":"rem-val","alarms":[{"relative_offset":"soon"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("relative_offset must be a number") == true)
    }

    @Test
    @MainActor
    func setReminderAlarmsRejectsNullAlarms() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"rem-val","alarms":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("alarms must be an array") == true)
    }
}

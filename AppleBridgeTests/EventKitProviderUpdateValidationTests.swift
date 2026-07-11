@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderUpdateValidation")
struct EventKitProviderUpdateValidationTests {
    @MainActor
    private func providerWithReminder(reminderID: String = "rem-val") -> (EventKitProvider, MockEventKitStore) {
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
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func updateReminderRejectsBooleanPriority() {
        let (provider, _) = providerWithReminder()

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-val","priority":true}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func updateReminderRejectsInvalidTimeZone() {
        let (provider, _) = providerWithReminder()

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-val","time_zone":"Not/A/Zone"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("time_zone must be a valid timezone identifier") == true)
    }

    @Test
    @MainActor
    func updateReminderRejectsNullIsCompleted() {
        let (provider, _) = providerWithReminder()

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-val","is_completed":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("is_completed must be a boolean") == true)
    }

    @Test
    @MainActor
    func updateReminderClearsNotesWhenNullProvided() {
        let (provider, mockStore) = providerWithReminder()
        mockStore.reminders[0].notes = "remove me"

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-val","notes":null}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.reminders[0].notes == nil)
    }
}

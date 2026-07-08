@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteValidation")
struct EventKitProviderDeleteValidationTests {
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
    func deleteReminderRejectsEmptyReminderID() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"calendar_item_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier must not be empty") == true)
    }
}

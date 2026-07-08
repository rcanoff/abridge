@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderMoveValidation")
struct EventKitProviderMoveValidationTests {
    @MainActor
    private func providerWithReminder(reminderID: String = "rem-val") -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [
            mockStore.makeTestCalendar(calendarIdentifier: "list-val"),
            mockStore.makeTestCalendar(calendarIdentifier: "list-other"),
        ]
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
    func moveReminderRejectsEmptyReminderID() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"   ","calendar_identifier":"list-other"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier must not be empty") == true)
    }

    @Test
    @MainActor
    func moveReminderRejectsEmptyCalendarIdentifier() {
        let provider = providerWithReminder()

        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-val","calendar_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier must not be empty") == true)
    }
}

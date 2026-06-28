@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDelete")
struct EventKitProviderDeleteTests {
    @Test
    @MainActor
    func deleteReminderReturnsSuccessEnvelope() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-delete-1",
                calendarIdentifier: "list-delete",
                title: "Remove me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_id":"rem-delete-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_item_identifier\":\"rem-delete-1\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(!response.payloadJson.contains("\"reminder_id\""))
        #expect(mockStore.reminders.isEmpty)
    }

    @Test
    @MainActor
    func deleteReminderMissingReminderIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "delete_reminder", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("reminder_id is required") == true)
    }

    @Test
    @MainActor
    func deleteReminderDoesNotTrimReminderIDForLookup() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-delete-1",
                calendarIdentifier: "list-delete",
                title: "Remove me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_id":" rem-delete-1 "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown reminder_id:  rem-delete-1 ") == true)
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders.first?.calendarItemIdentifier == "rem-delete-1")
    }

    @Test
    @MainActor
    func deleteReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_id":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown reminder_id") == true)
    }

    @Test
    @MainActor
    func deleteReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_id":"rem-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

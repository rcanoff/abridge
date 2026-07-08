@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderComplete")
struct EventKitProviderCompleteTests {
    @Test
    @MainActor
    func completeReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-complete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-complete-1",
                calendarIdentifier: "list-complete",
                title: "Finish task",
                notes: "unchanged"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "complete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-complete-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Finish task"))
        #expect(response.payloadJson.contains("unchanged"))
        #expect(response.payloadJson.contains("\"is_completed\":true"))
        #expect(response.payloadJson.contains("completion_date"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].isCompleted == true)
        #expect(mockStore.reminders[0].completionDate != nil)
    }

    @Test
    @MainActor
    func uncompleteReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-uncomplete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-uncomplete-1",
                calendarIdentifier: "list-uncomplete",
                title: "Reopen task",
                isCompleted: true,
                notes: "still here"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "uncomplete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-uncomplete-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Reopen task"))
        #expect(response.payloadJson.contains("still here"))
        #expect(response.payloadJson.contains("\"is_completed\":false"))
        #expect(response.payloadJson.contains("completion_date"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].isCompleted == false)
        #expect(mockStore.reminders[0].completionDate == nil)
    }

    @Test
    @MainActor
    func completeReminderMissingReminderIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "complete_reminder", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier is required") == true)
    }

    @Test
    @MainActor
    func uncompleteReminderMissingReminderIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "uncomplete_reminder", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier is required") == true)
    }

    @Test
    @MainActor
    func completeReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "complete_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func uncompleteReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "uncomplete_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func completeReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "complete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func uncompleteReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "uncomplete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderCreate")
struct EventKitProviderCreateTests {
    @Test
    @MainActor
    func createReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create","title":"New task","notes":"detail"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("New task"))
        #expect(response.payloadJson.contains("list-create"))
        #expect(response.payloadJson.contains("detail"))
        #expect(mockStore.reminders.count == 1)
    }

    @Test
    @MainActor
    func createReminderAppliesOptionalFields() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-2")]
        let provider = EventKitProvider(store: mockStore)

        let payloadJson = """
        {"calendar_identifier":"list-create-2","title":"Priority task","priority":5,\
        "due_date_components":{"year":2026,"month":6,"day":28}}
        """
        let response = provider.handle(operation: "create_reminder", payloadJson: payloadJson)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"priority\":5"))
        #expect(response.payloadJson.contains("due_date_components"))
        #expect(response.payloadJson.contains("2026"))
    }

    @Test
    @MainActor
    func createReminderMissingCalendarIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"title":"No list"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier is required") == true)
    }

    @Test
    @MainActor
    func createReminderMissingTitleReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-3")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-3"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("title is required") == true)
    }

    @Test
    @MainActor
    func createReminderUnknownCalendarReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"missing-list","title":"Task"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func createReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create","title":"Task"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidPriority() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-4")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-4","title":"Bad priority","priority":10}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("priority must be between 0 and 9") == true)
    }
}

@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteList")
struct EventKitProviderDeleteListTests {
    @Test
    @MainActor
    func deleteListReturnsSuccessEnvelope() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [
            mockStore.makeTestCalendar(calendarIdentifier: "list-delete"),
            mockStore.makeTestCalendar(calendarIdentifier: "list-keep"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":"list-delete"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"deleted\":true"))
        #expect(response.payloadJson.contains("\"calendar_identifier\":\"list-delete\""))
        #expect(mockStore.calendars.count == 1)
        #expect(mockStore.calendars.first?.calendarIdentifier == "list-keep")
    }

    @Test
    @MainActor
    func deleteListMissingCalendarIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "delete_list", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier is required") == true)
    }

    @Test
    @MainActor
    func deleteListUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func deleteListRejectsEmptyCalendarIdentifier() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-val")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier must not be empty") == true)
    }

    @Test
    @MainActor
    func deleteListPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":"list-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

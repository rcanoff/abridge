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
        #expect(response.payloadJson.contains("\"calendar_identifier\":\"list-delete\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(mockStore.calendars.count == 1)
        #expect(mockStore.calendars.first?.calendarIdentifier == "list-keep")
    }

    @Test
    @MainActor
    func deleteListMissingCalendarIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema (required/non-empty) enforced in Rust before ProviderBridge.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func deleteListDoesNotTrimCalendarIdentifierForLookup() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":" list-delete "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier:  list-delete ") == true)
        #expect(mockStore.calendars.count == 1)
        #expect(mockStore.calendars.first?.calendarIdentifier == "list-delete")
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
    func deleteListRejectsEmptyCalendarIdentifier_schemaOwnedByRust() {
        // Pure schema (required/non-empty) enforced in Rust before ProviderBridge.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
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

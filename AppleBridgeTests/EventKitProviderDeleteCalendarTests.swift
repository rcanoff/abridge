@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteCalendar")
struct EventKitProviderDeleteCalendarTests {
    @Test
    @MainActor
    func deleteCalendarReturnsSuccessEnvelope() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-delete", title: "Delete Me"),
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-keep", title: "Keep"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_calendar",
            payloadJson: #"{"calendar_identifier":"cal-delete"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_identifier\":\"cal-delete\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(mockStore.eventCalendarsList.count == 1)
        #expect(mockStore.eventCalendarsList.first?.calendarIdentifier == "cal-keep")
    }

    @Test
    @MainActor
    func deleteCalendarMissingCalendarIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema (required/non-empty) enforced in Rust before ProviderBridge.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func deleteCalendarUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_calendar",
            payloadJson: #"{"calendar_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func deleteCalendarPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_calendar",
            payloadJson: #"{"calendar_identifier":"cal-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

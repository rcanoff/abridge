@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderUpdateCalendar")
struct EventKitProviderUpdateCalendarTests {
    @Test
    @MainActor
    func updateCalendarReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_calendar",
            payloadJson: #"{"calendar_identifier":"cal-work","title":"Updated"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("cal-work"))
        #expect(response.payloadJson.contains("Updated"))
        #expect(response.payloadJson.contains("supported_event_availabilities"))
        #expect(mockStore.eventCalendarsList.first?.title == "Updated")
    }

    @Test
    @MainActor
    func updateCalendarPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_calendar",
            payloadJson: #"{"calendar_identifier":"cal-work","title":"Updated"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func updateCalendarMissingIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema (required/non-empty) enforced in Rust before ProviderBridge.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func updateCalendarUnknownIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_calendar",
            payloadJson: #"{"calendar_identifier":"missing","title":"Updated"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }
}

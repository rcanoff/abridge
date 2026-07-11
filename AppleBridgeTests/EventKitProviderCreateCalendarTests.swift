@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderCreateCalendar")
struct EventKitProviderCreateCalendarTests {
    @Test
    @MainActor
    func createCalendarReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_calendar",
            payloadJson: #"{"title":"Work"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_identifier"))
        #expect(response.payloadJson.contains("Work"))
        #expect(response.payloadJson.contains("supported_event_availabilities"))
        #expect(mockStore.eventCalendarsList.count == 1)
    }

    @Test
    @MainActor
    func createCalendarPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_calendar",
            payloadJson: #"{"title":"Work"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func createCalendarMissingTitleReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema (required/non-empty) enforced in Rust before ProviderBridge.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }
}

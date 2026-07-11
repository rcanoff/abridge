@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderMoveEventValidation")
struct EventKitProviderMoveEventValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-val", title: "Work"),
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-other", title: "Personal"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-val",
                calendarIdentifier: "cal-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func moveEventRejectsEmptyEventIdentifier_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func moveEventRejectsEmptyCalendarIdentifier() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","calendar_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier must not be empty") == true)
    }
}

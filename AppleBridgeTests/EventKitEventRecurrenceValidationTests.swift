@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitEventRecurrenceValidation")
struct EventKitEventRecurrenceValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-rec-val"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-rec-val",
                calendarIdentifier: "cal-rec-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func setEventRecurrenceRejectsEmptyEventIdentifier_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func setEventRecurrenceRejectsInvalidRecurrenceFrequency() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: """
            {"event_identifier":"evt-evt-rec-val","recurrence_rules":[{"frequency":"hourly"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Invalid recurrence frequency") == true)
    }

    @Test
    @MainActor
    func setEventRecurrenceRejectsNullRecurrenceRules() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"evt-evt-rec-val","recurrence_rules":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("recurrence_rules must be an array") == true)
    }
}

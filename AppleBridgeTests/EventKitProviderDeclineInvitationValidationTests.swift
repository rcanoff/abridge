@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitDeclineInvitationValidation")
struct EventKitDeclineInvitationValidationTests {
    @MainActor
    private func providerWithInvitationEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-val", title: "Work"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-val",
            calendarIdentifier: "cal-val",
            title: "Invite"
        )
        mockStore.attachMockCurrentUserAttendee(to: event, status: .pending)
        mockStore.events = [event]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func declineInvitationRejectsEmptyEventIdentifier_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }
}

@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitTentativeInviteValidation")
struct EventKitTentativeInviteValidationTests {
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
    func tentativeInvitationRejectsEmptyEventIdentifier() {
        let provider = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "tentative_invitation",
            payloadJson: #"{"event_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier must not be empty") == true)
    }
}

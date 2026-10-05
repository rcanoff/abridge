@testable import ABridge
import Testing

@Suite("EventKitInvitationResponse")
struct EventKitInvitationResponseTests {
    @Test
    @MainActor
    func canRespondReturnsFalseForEventWithoutAttendees() {
        let event = EventKitTestSupport.makeEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Solo"
        )

        #expect(EventKitInvitationResponse.canRespond(to: event) == false)
    }
}

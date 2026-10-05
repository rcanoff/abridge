@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("LiveEventKitStoreInvitationContract", .serialized)
struct LiveEventKitStoreInvitationContractTests {
    @MainActor
    private func makeEligibleInvitationEvent() -> EKEvent {
        let eventStore = EKEventStore()
        let event = EventKitTestSupport.makeEvent(
            eventStore: eventStore,
            calendarItemIdentifier: "evt-live-contract-1",
            calendarIdentifier: "cal-live-contract",
            title: "Team sync"
        )
        EventKitMockParticipantSupport.attachCurrentUserAttendee(
            to: event,
            eventStore: eventStore,
            status: .pending
        )
        #expect(EventKitInvitationResponse.canRespond(to: event) == true)
        return event
    }

    @Test
    @MainActor
    func acceptEventInvitationThrowsUnsupportedEventKitError() {
        let store = LiveEventKitStore()
        let event = makeEligibleInvitationEvent()

        #expect(throws: EventKitProviderError.eventKitError(
            "Accepting calendar invitations is not supported via public EventKit API on macOS"
        )) {
            try store.acceptEventInvitation(event)
        }
    }

    @Test
    @MainActor
    func declineEventInvitationThrowsUnsupportedEventKitError() {
        let store = LiveEventKitStore()
        let event = makeEligibleInvitationEvent()

        #expect(throws: EventKitProviderError.eventKitError(
            "Declining calendar invitations is not supported via public EventKit API on macOS"
        )) {
            try store.declineEventInvitation(event)
        }
    }

    @Test
    @MainActor
    func tentativeEventInvitationThrowsUnsupportedEventKitError() {
        let store = LiveEventKitStore()
        let event = makeEligibleInvitationEvent()

        #expect(throws: EventKitProviderError.eventKitError(
            "Marking calendar invitations tentative is not supported via public EventKit API on macOS"
        )) {
            try store.tentativeEventInvitation(event)
        }
    }
}

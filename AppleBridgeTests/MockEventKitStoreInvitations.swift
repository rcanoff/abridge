@testable import AppleBridge
import EventKit

extension MockEventKitStore {
    func attachMockCurrentUserAttendee(
        to event: EKEvent,
        status: EKParticipantStatus = .pending
    ) {
        EventKitMockParticipantSupport.attachCurrentUserAttendee(
            to: event,
            eventStore: eventStore,
            status: status
        )
    }

    func canRespondToInvitation(for event: EKEvent) -> Bool {
        EventKitInvitationResponse.canRespond(to: event)
    }

    func acceptEventInvitation(_ event: EKEvent) throws {
        guard canRespondToInvitation(for: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        guard let currentUser = EventKitMockParticipantSupport.currentUserAttendee(on: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        EventKitMockParticipantSupport.setParticipantStatus(.accepted, on: currentUser)
        acceptedInvitationEventIDs.insert(event.calendarItemIdentifier)
    }

    func declineEventInvitation(_ event: EKEvent) throws {
        guard canRespondToInvitation(for: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        guard let currentUser = EventKitMockParticipantSupport.currentUserAttendee(on: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        EventKitMockParticipantSupport.setParticipantStatus(.declined, on: currentUser)
        declinedInvitationEventIDs.insert(event.calendarItemIdentifier)
    }

    func tentativeEventInvitation(_ event: EKEvent) throws {
        guard canRespondToInvitation(for: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        guard let currentUser = EventKitMockParticipantSupport.currentUserAttendee(on: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        EventKitMockParticipantSupport.setParticipantStatus(.tentative, on: currentUser)
        tentativeInvitationEventIDs.insert(event.calendarItemIdentifier)
    }
}

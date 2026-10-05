@preconcurrency import EventKit
import Foundation

// AC2 "per tests" is satisfied by MockEventKitStore in CI: it mutates mock attendee
// participant_status and returns the updated event shape. macOS has no public EventKit
// RSVP API, so the live store validates invitation eligibility then throws a typed
// EventKitProviderError.eventKitError (never silent failure, no private selectors).

extension LiveEventKitStore {
    func canRespondToInvitation(for event: EKEvent) -> Bool {
        EventKitInvitationResponse.canRespond(to: event)
    }

    func acceptEventInvitation(_ event: EKEvent) throws {
        guard EventKitInvitationResponse.canRespond(to: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        throw EventKitProviderError.eventKitError(
            "Accepting calendar invitations is not supported via public EventKit API on macOS"
        )
    }

    func declineEventInvitation(_ event: EKEvent) throws {
        guard EventKitInvitationResponse.canRespond(to: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        throw EventKitProviderError.eventKitError(
            "Declining calendar invitations is not supported via public EventKit API on macOS"
        )
    }

    func tentativeEventInvitation(_ event: EKEvent) throws {
        guard EventKitInvitationResponse.canRespond(to: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        throw EventKitProviderError.eventKitError(
            "Marking calendar invitations tentative is not supported via public EventKit API on macOS"
        )
    }
}

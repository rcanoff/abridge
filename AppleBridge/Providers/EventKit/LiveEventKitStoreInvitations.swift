@preconcurrency import EventKit
import Foundation

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

    func tentativeEventInvitation(_ event: EKEvent) throws {
        guard EventKitInvitationResponse.canRespond(to: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        throw EventKitProviderError.eventKitError(
            "Marking calendar invitations tentative is not supported via public EventKit API on macOS"
        )
    }
}

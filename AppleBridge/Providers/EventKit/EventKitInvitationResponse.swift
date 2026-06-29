@preconcurrency import EventKit
import Foundation

enum EventKitInvitationResponse {
    private static let setAttendeeStatusSelector = Selector(("setAttendeeStatus:"))

    static func isSupported(on event: EKEvent) -> Bool {
        event.responds(to: setAttendeeStatusSelector)
    }

    static func canRespond(to event: EKEvent) -> Bool {
        guard event.hasAttendees,
              let attendees = event.attendees,
              let selfAttendee = attendees.first(where: { $0.isCurrentUser })
        else {
            return false
        }

        switch selfAttendee.participantStatus {
        case .pending, .unknown, .tentative:
            return true
        default:
            return false
        }
    }

    static func accept(on event: EKEvent) throws {
        guard canRespond(to: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        guard isSupported(on: event) else {
            throw EventKitProviderError.eventKitError(
                "EventKit does not support accepting invitations on this platform"
            )
        }

        _ = event.perform(
            setAttendeeStatusSelector,
            with: NSNumber(value: EKParticipantStatus.accepted.rawValue)
        )
    }
}

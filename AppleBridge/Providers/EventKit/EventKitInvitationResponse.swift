@preconcurrency import EventKit
import Foundation

enum EventKitInvitationResponse {
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
}

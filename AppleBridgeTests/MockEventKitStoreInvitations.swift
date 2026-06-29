@testable import AppleBridge
import EventKit

extension MockEventKitStore {
    func canRespondToInvitation(for event: EKEvent) -> Bool {
        invitationRespondableEventIDs.contains(event.calendarItemIdentifier)
    }

    func acceptEventInvitation(_ event: EKEvent) throws {
        guard canRespondToInvitation(for: event) else {
            throw EventKitProviderError.invalidArguments("Event has no invitation for the current user")
        }
        acceptedInvitationEventIDs.insert(event.calendarItemIdentifier)
    }
}

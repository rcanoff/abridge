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
}

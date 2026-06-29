@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderDeclineInvitation")
struct EventKitProviderDeclineInvitationTests {
    private static let eventReadKeys: Set<String> = [
        "calendar_item_identifier",
        "calendar_item_external_identifier",
        "calendar",
        "title",
        "location",
        "url",
        "notes",
        "creation_date",
        "last_modified_date",
        "has_alarms",
        "has_recurrence_rules",
        "has_notes",
        "has_attendees",
        "time_zone",
        "attendees",
        "event_identifier",
        "availability",
        "start_date",
        "end_date",
        "is_all_day",
        "occurrence_date",
        "is_detached",
        "status",
        "birthday_contact_identifier",
        "organizer",
        "structured_location",
        "alarms",
        "recurrence_rules",
    ]

    @MainActor
    private func providerWithInvitationEvent() -> (EventKitProvider, MockEventKitStore) {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-invite", title: "Work"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-invite-1",
            calendarIdentifier: "cal-invite",
            title: "Team sync"
        )
        mockStore.invitationRespondableEventIDs = ["evt-invite-1"]
        mockStore.events = [event]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func declineInvitationReturnsFullEventShape() throws {
        let (provider, _) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-invite-1"}"#
        )

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Self.eventReadKeys)
        #expect(object["title"] as? String == "Team sync")
    }

    @Test
    @MainActor
    func declineInvitationRecordsDeclinedInvitation() {
        let (provider, mockStore) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-invite-1"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.declinedInvitationEventIDs.contains("evt-invite-1"))
    }

    @Test
    @MainActor
    func declineInvitationMissingEventIdentifierReturnsInvalidArguments() {
        let (provider, _) = providerWithInvitationEvent()

        let response = provider.handle(operation: "decline_invitation", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier is required") == true)
    }

    @Test
    @MainActor
    func declineInvitationUnknownIDReturnsInvalidArguments() {
        let (provider, mockStore) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
        #expect(mockStore.events.count == 1)
    }

    @Test
    @MainActor
    func declineInvitationWithoutRespondableInvitationReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-invite", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-no-invite",
                calendarIdentifier: "cal-invite",
                title: "Solo event"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-no-invite"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("no invitation for the current user") == true)
    }

    @Test
    @MainActor
    func declineInvitationPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"evt-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

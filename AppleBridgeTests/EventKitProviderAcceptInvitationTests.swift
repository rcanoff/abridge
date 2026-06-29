@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderAcceptInvitation", .serialized)
struct EventKitProviderAcceptInvitationTests {
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
        mockStore.attachMockCurrentUserAttendee(to: event, status: .pending)
        mockStore.events = [event]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func acceptInvitationReturnsFullEventShape() throws {
        let (provider, _) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-invite-1"}"#
        )

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Self.eventReadKeys)
        #expect(object["title"] as? String == "Team sync")
        #expect(object["has_attendees"] as? Bool == true)
        let attendees = try #require(object["attendees"] as? [[String: Any]])
        #expect(attendees.count == 1)
        #expect(attendees[0]["participant_status"] as? String == "accepted")
        #expect(attendees[0]["is_current_user"] as? Bool == true)
    }

    @Test
    @MainActor
    func acceptInvitationRecordsAcceptedInvitation() {
        let (provider, mockStore) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-invite-1"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.acceptedInvitationEventIDs.contains("evt-invite-1"))
    }

    @Test
    @MainActor
    func acceptInvitationMissingEventIdentifierReturnsInvalidArguments() {
        let (provider, _) = providerWithInvitationEvent()

        let response = provider.handle(operation: "accept_invitation", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier is required") == true)
    }

    @Test
    @MainActor
    func acceptInvitationUnknownIDReturnsInvalidArguments() {
        let (provider, mockStore) = providerWithInvitationEvent()

        let response = provider.handle(
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
        #expect(mockStore.events.count == 1)
    }

    @Test
    @MainActor
    func acceptInvitationWithoutRespondableInvitationReturnsInvalidArguments() {
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
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-no-invite"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("no invitation for the current user") == true)
    }

    @Test
    @MainActor
    func acceptInvitationPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"evt-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

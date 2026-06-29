@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderGetEvent")
struct EventKitProviderGetEventTests {
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

    @Test
    @MainActor
    func getEventReturnsFaithfulEventShape() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup",
                startDate: start,
                endDate: end
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let event = try #require(decoded as? [String: Any])

        #expect(Set(event.keys) == Self.eventReadKeys)
        #expect(event["calendar_item_identifier"] as? String == "evt-1")
        #expect(event["event_identifier"] as? String == "evt-evt-1")
        #expect(event["title"] as? String == "Standup")
    }

    @Test
    @MainActor
    func getEventPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func getEventMissingEventIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_event",
            payloadJson: #"{}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier is required") == true)
    }

    @Test
    @MainActor
    func getEventUnknownEventIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }
}
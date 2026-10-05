@testable import ABridge
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
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let createResponse = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Standup",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T23:13:20Z"}
            """
        )
        #expect(createResponse.ok == true)

        let createData = try #require(createResponse.payloadJson.data(using: .utf8))
        let created = try #require(
            try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        )
        let eventIdentifier = try #require(created["event_identifier"] as? String)

        let getResponse = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"\#(eventIdentifier)"}"#
        )
        #expect(getResponse.ok == true)

        let data = try #require(getResponse.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let event = try #require(decoded as? [String: Any])

        #expect(Set(event.keys) == Self.eventReadKeys)
        #expect(event["event_identifier"] as? String == eventIdentifier)
        #expect(event["title"] as? String == "Standup")
        #expect((event["calendar"] as? [String: Any])?["calendar_identifier"] as? String == "cal-work")
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

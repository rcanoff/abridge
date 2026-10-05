@testable import ABridge
import Foundation
import Testing

@Suite("EventKitProviderListEvents")
struct EventKitProviderListEventsTests {
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
    func listEventsReturnsFaithfulEventShape() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup",
                startDate: start,
                endDate: end
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_events",
            payloadJson: #"{"start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-15T22:13:20Z"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let events = try #require(decoded as? [[String: Any]])
        let first = try #require(events.first)

        #expect(Set(first.keys) == Self.eventReadKeys)
        #expect(first["calendar_item_identifier"] as? String == "evt-1")
        #expect(first["title"] as? String == "Standup")
    }

    @Test
    @MainActor
    func listEventsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_events",
            payloadJson: #"{"start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-15T22:13:20Z"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

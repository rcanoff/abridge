@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderListCalendars")
struct EventKitProviderListCalendarsTests {
    private static let calendarReadKeys: Set<String> = [
        "calendar_identifier",
        "title",
        "type",
        "source",
        "cg_color",
        "allowed_entity_types",
        "supported_event_availabilities",
        "allows_content_modifications",
        "is_immutable",
        "is_subscribed",
    ]

    @Test
    @MainActor
    func listCalendarsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "list_calendars", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func listCalendarsReturnsFaithfulCalendarShape() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "list_calendars", payloadJson: "{}")

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let calendars = decoded as? [[String: Any]], let first = calendars.first else {
            Issue.record("Expected array of calendar objects")
            return
        }

        #expect(Set(first.keys) == Self.calendarReadKeys)
        #expect(first["calendar_identifier"] as? String == "cal-work")
        #expect(first["title"] as? String == "Work")
        let allowedTypes = first["allowed_entity_types"] as? [String]
        #expect(allowedTypes?.contains("event") == true)
    }
}

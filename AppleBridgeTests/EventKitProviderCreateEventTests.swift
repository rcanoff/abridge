@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderCreateEvent")
struct EventKitProviderCreateEventTests {
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
    func createEventReturnsFaithfulEventShape() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Standup",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T22:43:20Z"}
            """
        )

        #expect(response.ok == true)
        #expect(mockStore.events.count == 1)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let event = try #require(decoded as? [String: Any])

        #expect(Set(event.keys) == Self.eventReadKeys)
        #expect(event["title"] as? String == "Standup")
        #expect((event["calendar"] as? [String: Any])?["calendar_identifier"] as? String == "cal-work")
        #expect((event["event_identifier"] as? String)?.isEmpty == false)
    }

    @Test
    @MainActor
    func createEventAppliesOptionalFields() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Offsite","notes":"Bring badge",\
            "location":"HQ","is_all_day":true,"availability":"busy",\
            "start_date":"2023-11-14T00:00:00Z","end_date":"2023-11-15T00:00:00Z"}
            """
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Offsite"))
        #expect(response.payloadJson.contains("Bring badge"))
        #expect(response.payloadJson.contains("HQ"))
        #expect(response.payloadJson.contains("\"is_all_day\":true"))
        #expect(response.payloadJson.contains("\"availability\":\"not_supported\""))
    }

    @Test
    @MainActor
    func createEventMissingCalendarIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func createEventMissingTitleReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func createEventUnknownCalendarReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"missing-cal","title":"Event",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T22:43:20Z"}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func createEventStartAfterEndReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Bad range",\
            "start_date":"2023-11-15T22:13:20Z","end_date":"2023-11-14T22:13:20Z"}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("start_date must not be after end_date") == true)
    }

    @Test
    @MainActor
    func createEventPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Event",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T22:43:20Z"}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

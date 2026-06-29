@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitSerializationEvent")
struct EventKitSerializationEventTests {
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
    func eventJSONObjectIncludesAllRequiredKeys() {
        let event = EventKitTestSupport.makeEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Meeting"
        )

        let keys = Set(EventKitSerialization.eventJSONObject(from: event).keys)

        #expect(keys == Self.eventReadKeys)
    }

    @Test
    @MainActor
    func eventJSONObjectSerializesEventIdentifier() {
        let event = EventKitTestSupport.makeEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Meeting"
        )

        let payload = EventKitSerialization.eventJSONObject(from: event)

        #expect(payload["event_identifier"] is NSNull)
    }

    @Test
    @MainActor
    func eventJSONObjectIsJSONSerializable() throws {
        let event = EventKitTestSupport.makeEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Meeting"
        )

        let payload = EventKitSerialization.eventJSONObject(from: event)
        _ = try JSONSerialization.data(withJSONObject: payload)
    }
}

@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventKitSerialization")
struct EventKitSerializationTests {
    private static let reminderReadKeys: Set<String> = [
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
        "is_completed",
        "completion_date",
        "priority",
        "due_date_components",
        "start_date_components",
        "alarms",
        "recurrence_rules",
    ]

    private static let calendarReadKeys: Set<String> = [
        "calendar_identifier",
        "title",
        "type",
        "source",
        "color",
        "allowed_entity_types",
        "allows_content_modifications",
        "is_immutable",
        "is_subscribed",
    ]

    @Test
    @MainActor
    func reminderJSONObjectIncludesAllRequiredKeys() {
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-1",
            calendarIdentifier: "list-1",
            title: "Buy milk",
            notes: "2%"
        )

        let keys = Set(EventKitSerialization.reminderJSONObject(from: reminder).keys)

        #expect(keys == Self.reminderReadKeys)
    }

    @Test
    @MainActor
    func reminderJSONObjectSerializesAbsentValuesFaithfully() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-2")

        let object = EventKitSerialization.reminderJSONObject(from: reminder)

        // EventKit defaults unset title to "" rather than nil — serialize as-is.
        #expect(object["title"] as? String == "")
        #expect(object["notes"] is NSNull)
        #expect(object["calendar"] is NSNull)
        #expect(object["due_date_components"] is NSNull)
    }

    @Test
    @MainActor
    func reminderJSONObjectNestedCalendarUsesFaithfulKeys() {
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-3",
            calendarIdentifier: "list-abc",
            title: "Task"
        )

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let calendar = object["calendar"] as? [String: Any] else {
            Issue.record("Expected nested calendar object")
            return
        }

        #expect(calendar["calendar_identifier"] as? String == "list-abc")
        #expect(Set(calendar.keys).isSuperset(of: ["source", "type", "color"]))
    }

    @Test
    @MainActor
    func calendarJSONObjectIncludesAllRequiredKeys() {
        let calendar = EventKitTestSupport.makeCalendar(calendarIdentifier: "cal-1", title: "Groceries")

        let keys = Set(EventKitSerialization.calendarJSONObject(from: calendar).keys)

        #expect(keys == Self.calendarReadKeys)
    }

    @Test
    func encodesJSONRoundTrip() throws {
        let json = try EventKitSerialization.jsonString(from: ["calendar_item_identifier": "x"])
        #expect(json.contains("calendar_item_identifier"))
    }
}

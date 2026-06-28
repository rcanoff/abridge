@testable import AppleBridge
import CoreGraphics
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
        "time_zone",
        "attendees",
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
        "cg_color",
        "allowed_entity_types",
        "allows_content_modifications",
        "is_immutable",
        "is_subscribed",
    ]

    private static let cgColorReadKeys: Set<String> = [
        "color_space_name",
        "color_space_model",
        "number_of_components",
        "components",
        "alpha",
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
        #expect(object["time_zone"] is NSNull)
        #expect((object["attendees"] as? [Any])?.isEmpty == true)
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
        #expect(Set(calendar.keys).isSuperset(of: ["source", "type", "cg_color"]))
    }

    @Test
    @MainActor
    func calendarJSONObjectIncludesAllRequiredKeys() {
        let calendar = EventKitTestSupport.makeCalendar(calendarIdentifier: "cal-1", title: "Groceries")

        let keys = Set(EventKitSerialization.calendarJSONObject(from: calendar).keys)

        #expect(keys == Self.calendarReadKeys)
    }

    @Test
    @MainActor
    func calendarJSONObjectSerializesCGColorFaithfully() {
        let calendar = EventKitTestSupport.makeCalendar(calendarIdentifier: "cal-color", title: "Colored")
        calendar.cgColor = CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8)

        let object = EventKitSerialization.calendarJSONObject(from: calendar)
        guard let cgColor = object["cg_color"] as? [String: Any] else {
            Issue.record("Expected structured cg_color object")
            return
        }

        #expect(Set(cgColor.keys) == Self.cgColorReadKeys)
        #expect(cgColor["number_of_components"] as? Int == 4)
        #expect(cgColor["alpha"] as? CGFloat == 0.8)

        let components = cgColor["components"] as? [CGFloat]
        #expect(components?.count == 4)
        #expect(components?[0] == 0.25)
        #expect(components?[1] == 0.5)
        #expect(components?[2] == 0.75)
        #expect(components?[3] == 0.8)
        #expect(cgColor["color_space_model"] as? String == "rgb")
    }

    @Test
    func encodesJSONRoundTrip() throws {
        let json = try EventKitSerialization.jsonString(from: ["calendar_item_identifier": "x"])
        #expect(json.contains("calendar_item_identifier"))
    }

    @Test
    @MainActor
    func recurrenceRuleJSONObjectSerializesNilOptionalArraysAsNull() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-rec")
        reminder.recurrenceRules = [
            EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil),
        ]

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let rules = object["recurrence_rules"] as? [[String: Any]],
              let rule = rules.first
        else {
            Issue.record("Expected recurrence_rules array with one rule")
            return
        }

        let nilOptionalArrayKeys = [
            "days_of_the_week",
            "days_of_the_month",
            "days_of_the_year",
            "months_of_the_year",
            "weeks_of_the_year",
            "set_positions",
        ]

        for key in nilOptionalArrayKeys {
            #expect(rule[key] is NSNull, "Expected \(key) to serialize as null when unset")
        }
    }

    @Test
    @MainActor
    func recurrenceRuleJSONObjectSerializesPresentOptionalArrays() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-rec-weekly")
        reminder.recurrenceRules = [
            EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 2,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
                daysOfTheMonth: [NSNumber(value: 15)],
                monthsOfTheYear: [NSNumber(value: 6)],
                weeksOfTheYear: [NSNumber(value: 3)],
                daysOfTheYear: [NSNumber(value: 180)],
                setPositions: [NSNumber(value: -1)],
                end: nil
            ),
        ]

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let rules = object["recurrence_rules"] as? [[String: Any]],
              let rule = rules.first
        else {
            Issue.record("Expected recurrence_rules array with one rule")
            return
        }

        let daysOfWeek = rule["days_of_the_week"] as? [[String: Any]]
        #expect(daysOfWeek?.count == 1)
        #expect(daysOfWeek?.first?["day_of_the_week"] as? Int == EKWeekday.monday.rawValue)

        #expect(rule["days_of_the_month"] as? [Int] == [15])
        #expect(rule["days_of_the_year"] as? [Int] == [180])
        #expect(rule["months_of_the_year"] as? [Int] == [6])
        #expect(rule["weeks_of_the_year"] as? [Int] == [3])
        #expect(rule["set_positions"] as? [Int] == [-1])
    }
}

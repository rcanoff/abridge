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

    private static let dateComponentsReadKeys: Set<String> = [
        "year",
        "month",
        "day",
        "hour",
        "minute",
        "second",
        "nanosecond",
        "weekday",
        "weekday_ordinal",
        "quarter",
        "week_of_month",
        "week_of_year",
        "year_for_week_of_year",
        "is_leap_month",
        "time_zone",
        "calendar",
    ]

    private static let foundationCalendarReadKeys: Set<String> = [
        "identifier",
        "locale",
        "time_zone",
        "first_weekday",
        "minimum_days_in_first_week",
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
    @MainActor
    func dateComponentsJSONObjectIncludesAllRequiredKeys() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-dc")
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.calendar = Calendar(identifier: .gregorian)
        reminder.dueDateComponents = components

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let dateComponents = object["due_date_components"] as? [String: Any] else {
            Issue.record("Expected due_date_components object")
            return
        }

        #expect(Set(dateComponents.keys) == Self.dateComponentsReadKeys)
    }

    @Test
    @MainActor
    func dateComponentsJSONObjectSerializesCalendarFaithfullyFromEventKit() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-dc-nil-cal")
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        reminder.dueDateComponents = components

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let dateComponents = object["due_date_components"] as? [String: Any] else {
            Issue.record("Expected due_date_components object")
            return
        }

        // EventKit supplies a default calendar when due components are set — serialize as-is.
        if reminder.dueDateComponents?.calendar == nil {
            #expect(dateComponents["calendar"] is NSNull)
        } else {
            #expect(dateComponents["calendar"] as? [String: Any] != nil)
        }
    }

    @Test
    @MainActor
    func dateComponentsJSONObjectSerializesPresentCalendarFaithfully() {
        let reminder = EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-dc-cal")
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 28
        components.calendar = Calendar(identifier: .gregorian)
        reminder.dueDateComponents = components

        let object = EventKitSerialization.reminderJSONObject(from: reminder)
        guard let dateComponents = object["due_date_components"] as? [String: Any],
              let calendar = dateComponents["calendar"] as? [String: Any]
        else {
            Issue.record("Expected nested calendar in due_date_components")
            return
        }

        #expect(Set(calendar.keys) == Self.foundationCalendarReadKeys)
        #expect(calendar["identifier"] as? String == "gregorian")
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

import EventKit
import Foundation

enum EventKitSerialization {
    // MARK: - Public serializers

    static func reminderJSONObject(from reminder: EKReminder) -> [String: Any] {
        var payload: [String: Any] = calendarItemJSONObject(from: reminder)
        payload["is_completed"] = reminder.isCompleted
        payload["completion_date"] = iso8601String(from: reminder.completionDate)
        payload["priority"] = reminder.priority
        payload["due_date_components"] = dateComponentsJSONObject(from: reminder.dueDateComponents)
        payload["start_date_components"] = dateComponentsJSONObject(from: reminder.startDateComponents)
        payload["alarms"] = optionalArrayJSONObject(from: reminder.alarms, map: alarmJSONObject)
        payload["recurrence_rules"] = optionalArrayJSONObject(
            from: reminder.recurrenceRules,
            map: recurrenceRuleJSONObject
        )
        return payload
    }

    static func calendarJSONObject(from calendar: EKCalendar) -> [String: Any] {
        var payload: [String: Any] = [
            "calendar_identifier": calendar.calendarIdentifier,
            "title": jsonValue(calendar.title),
            "type": calendarTypeString(calendar.type),
            "cg_color": cgColorJSONObject(from: calendar.cgColor),
            "allowed_entity_types": entityTypesArray(from: calendar.allowedEntityTypes),
            "supported_event_availabilities": eventAvailabilityArray(
                from: calendar.supportedEventAvailabilities
            ),
            "allows_content_modifications": calendar.allowsContentModifications,
            "is_immutable": calendar.isImmutable,
            "is_subscribed": calendar.isSubscribed,
        ]

        if let source = calendar.source {
            payload["source"] = sourceJSONObject(from: source)
        } else {
            payload["source"] = NSNull()
        }

        return payload
    }

    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EventKitProviderError.serializationFailed
        }
        return string
    }

    // MARK: - EKCalendarItem shared fields

    private static func calendarItemJSONObject(from item: EKCalendarItem) -> [String: Any] {
        var payload: [String: Any] = [
            "calendar_item_identifier": item.calendarItemIdentifier,
            "calendar_item_external_identifier": jsonValue(item.calendarItemExternalIdentifier),
            "title": jsonValue(item.title),
            "location": jsonValue(item.location),
            "url": urlString(from: item.url),
            "notes": jsonValue(item.notes),
            "creation_date": iso8601String(from: item.creationDate),
            "last_modified_date": iso8601String(from: item.lastModifiedDate),
            "has_alarms": item.hasAlarms,
            "has_recurrence_rules": item.hasRecurrenceRules,
            "has_notes": item.hasNotes,
            "has_attendees": item.hasAttendees,
            "time_zone": jsonValue(item.timeZone?.identifier),
            "attendees": optionalArrayJSONObject(from: item.attendees, map: participantJSONObject),
        ]

        if let calendar = item.calendar {
            payload["calendar"] = calendarJSONObject(from: calendar)
        } else {
            payload["calendar"] = NSNull()
        }

        return payload
    }

    // MARK: - Nested types

    private static func participantJSONObject(from participant: EKParticipant) -> [String: Any] {
        [
            "url": urlString(from: participant.url),
            "name": jsonValue(participant.name),
            "participant_status": participantStatusString(participant.participantStatus),
            "participant_role": participantRoleString(participant.participantRole),
            "participant_type": participantTypeString(participant.participantType),
            "is_current_user": participant.isCurrentUser,
            "contact_predicate": participant.contactPredicate.predicateFormat,
        ]
    }

    private static func sourceJSONObject(from source: EKSource) -> [String: Any] {
        [
            "source_identifier": source.sourceIdentifier,
            "title": jsonValue(source.title),
            "source_type": sourceTypeString(source.sourceType),
        ]
    }

    private static func alarmJSONObject(from alarm: EKAlarm) -> [String: Any] {
        var payload: [String: Any] = [
            "absolute_date": iso8601String(from: alarm.absoluteDate),
            "relative_offset": alarm.relativeOffset,
            "proximity": alarmProximityString(alarm.proximity),
            "type": alarmTypeString(alarm.type),
            "email_address": jsonValue(alarm.emailAddress),
        ]

        if let location = alarm.structuredLocation {
            payload["structured_location"] = structuredLocationJSONObject(from: location)
        } else {
            payload["structured_location"] = NSNull()
        }

        return payload
    }

    private static func structuredLocationJSONObject(from location: EKStructuredLocation) -> [String: Any] {
        var payload: [String: Any] = [
            "title": jsonValue(location.title),
            "radius": location.radius,
        ]

        if let geo = location.geoLocation {
            payload["geo_location"] = [
                "latitude": geo.coordinate.latitude,
                "longitude": geo.coordinate.longitude,
            ]
        } else {
            payload["geo_location"] = NSNull()
        }

        return payload
    }

    private static func recurrenceRuleJSONObject(from rule: EKRecurrenceRule) -> [String: Any] {
        var payload: [String: Any] = [
            "frequency": recurrenceFrequencyString(rule.frequency),
            "interval": rule.interval,
            "first_day_of_the_week": rule.firstDayOfTheWeek,
            "days_of_the_week": recurrenceDaysOfWeekArray(from: rule.daysOfTheWeek),
            "days_of_the_month": numberArray(from: rule.daysOfTheMonth),
            "days_of_the_year": numberArray(from: rule.daysOfTheYear),
            "months_of_the_year": numberArray(from: rule.monthsOfTheYear),
            "weeks_of_the_year": numberArray(from: rule.weeksOfTheYear),
            "set_positions": numberArray(from: rule.setPositions),
        ]

        if let end = rule.recurrenceEnd {
            payload["recurrence_end"] = recurrenceEndJSONObject(from: end)
        } else {
            payload["recurrence_end"] = NSNull()
        }

        return payload
    }

    private static func recurrenceEndJSONObject(from end: EKRecurrenceEnd) -> [String: Any] {
        [
            "end_date": iso8601String(from: end.endDate),
            "occurrence_count": end.occurrenceCount,
        ]
    }

    private static func dateComponentsJSONObject(from components: DateComponents?) -> Any {
        guard let components else { return NSNull() }

        var payload: [String: Any] = [
            "year": jsonValue(components.year),
            "month": jsonValue(components.month),
            "day": jsonValue(components.day),
            "hour": jsonValue(components.hour),
            "minute": jsonValue(components.minute),
            "second": jsonValue(components.second),
            "nanosecond": jsonValue(components.nanosecond),
            "weekday": jsonValue(components.weekday),
            "weekday_ordinal": jsonValue(components.weekdayOrdinal),
            "quarter": jsonValue(components.quarter),
            "week_of_month": jsonValue(components.weekOfMonth),
            "week_of_year": jsonValue(components.weekOfYear),
            "year_for_week_of_year": jsonValue(components.yearForWeekOfYear),
            "is_leap_month": jsonValue(components.isLeapMonth),
            "time_zone": jsonValue(components.timeZone?.identifier),
        ]

        if let calendar = components.calendar {
            payload["calendar"] = foundationCalendarJSONObject(from: calendar)
        } else {
            payload["calendar"] = NSNull()
        }

        return payload
    }

    private static func foundationCalendarJSONObject(from calendar: Calendar) -> [String: Any] {
        [
            "identifier": calendarIdentifierString(calendar.identifier),
            "locale": jsonValue(calendar.locale?.identifier),
            "time_zone": calendar.timeZone.identifier,
            "first_weekday": calendar.firstWeekday,
            "minimum_days_in_first_week": calendar.minimumDaysInFirstWeek,
        ]
    }

    // MARK: - Encoding helpers

    private static func optionalArrayJSONObject<Element>(
        from array: [Element]?,
        map: (Element) -> [String: Any]
    ) -> Any {
        guard let array else { return NSNull() }
        return array.map(map)
    }

    private static func jsonValue(_ string: String?) -> Any {
        string ?? NSNull()
    }

    private static func jsonValue(_ number: Int?) -> Any {
        number ?? NSNull()
    }

    private static func jsonValue(_ number: Bool?) -> Any {
        number ?? NSNull()
    }

    private static func iso8601String(from date: Date?) -> Any {
        guard let date else { return NSNull() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func urlString(from url: URL?) -> Any {
        url?.absoluteString ?? NSNull()
    }

    private static func cgColorJSONObject(from color: CGColor?) -> Any {
        guard let color else { return NSNull() }

        var payload: [String: Any] = [
            "number_of_components": color.numberOfComponents,
            "components": color.components ?? [],
            "alpha": color.alpha,
        ]

        if let colorSpace = color.colorSpace {
            payload["color_space_name"] = jsonValue(colorSpace.name as String?)
            payload["color_space_model"] = colorSpaceModelString(colorSpace.model)
        } else {
            payload["color_space_name"] = NSNull()
            payload["color_space_model"] = NSNull()
        }

        return payload
    }

    private static func numberArray(from numbers: [NSNumber]?) -> Any {
        numbers?.map(\.intValue) ?? NSNull()
    }

    private static func recurrenceDaysOfWeekArray(from days: [EKRecurrenceDayOfWeek]?) -> Any {
        guard let days else { return NSNull() }
        return days.map { day in
            [
                "day_of_the_week": day.dayOfTheWeek.rawValue,
                "week_number": day.weekNumber,
            ]
        }
    }

    private static func entityTypesArray(from mask: EKEntityMask) -> [String] {
        var types: [String] = []
        if mask.contains(.event) { types.append("event") }
        if mask.contains(.reminder) { types.append("reminder") }
        return types
    }

    private static func eventAvailabilityArray(from mask: EKCalendarEventAvailabilityMask) -> [String] {
        var availabilities: [String] = []
        if mask.contains(.busy) { availabilities.append("busy") }
        if mask.contains(.free) { availabilities.append("free") }
        if mask.contains(.tentative) { availabilities.append("tentative") }
        if mask.contains(.unavailable) { availabilities.append("unavailable") }
        return availabilities
    }
}

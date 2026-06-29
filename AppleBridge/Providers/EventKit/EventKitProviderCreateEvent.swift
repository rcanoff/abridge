@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct CreateEventArguments {
        let calendarIdentifier: String
        let title: String
        let notes: String?
        let location: String?
        let url: URL?
        let timeZone: TimeZone?
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool?
        let availability: EKEventAvailability?
        let structuredLocation: EKStructuredLocation?
        let alarms: [EKAlarm]?
        let recurrenceRules: [EKRecurrenceRule]?
    }

    func createEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseCreateEventArguments(payloadJson)
            let calendars = try eventCalendars(calendarIdentifier: arguments.calendarIdentifier)
            guard let calendar = calendars.first else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown calendar_identifier: \(arguments.calendarIdentifier)"
                )
            }

            let event = store.makeEvent()
            try applyCreateEventArguments(arguments, to: event, calendar: calendar)
            try store.saveEvent(event, commit: true)

            let payload = try EventKitSerialization.jsonString(
                from: EventKitSerialization.eventJSONObject(from: event)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func applyCreateEventArguments(
        _ arguments: CreateEventArguments,
        to event: EKEvent,
        calendar: EKCalendar
    ) throws {
        event.calendar = calendar
        event.title = arguments.title
        event.startDate = arguments.startDate
        event.endDate = arguments.endDate

        if let notes = arguments.notes { event.notes = notes }
        if let location = arguments.location { event.location = location }
        if let url = arguments.url { event.url = url }
        if let timeZone = arguments.timeZone { event.timeZone = timeZone }
        if let isAllDay = arguments.isAllDay { event.isAllDay = isAllDay }
        if let availability = arguments.availability { event.availability = availability }
        if let structuredLocation = arguments.structuredLocation {
            event.structuredLocation = structuredLocation
        }
        if let alarms = arguments.alarms { event.alarms = alarms }
        if let recurrenceRules = arguments.recurrenceRules { event.recurrenceRules = recurrenceRules }
    }

    private func parseCreateEventArguments(_ payloadJson: String) throws -> CreateEventArguments {
        let dictionary = try parseCreateEventDictionary(payloadJson)
        let calendarIdentifier = try requiredNonEmptyString(named: "calendar_identifier", in: dictionary)
        let title = try requiredNonEmptyString(named: "title", in: dictionary)
        let (startDate, endDate) = try requiredEventDateRange(in: dictionary)

        return try CreateEventArguments(
            calendarIdentifier: calendarIdentifier,
            title: title,
            notes: EventKitDeserialization.optionalString(dictionary["notes"]),
            location: EventKitDeserialization.optionalString(dictionary["location"]),
            url: EventKitDeserialization.optionalURL(dictionary["url"]),
            timeZone: optionalTimeZone(from: dictionary),
            startDate: startDate,
            endDate: endDate,
            isAllDay: EventKitDeserialization.optionalBool(dictionary["is_all_day"]),
            availability: EventKitDeserialization.eventAvailability(from: dictionary["availability"]),
            structuredLocation: EventKitDeserialization.structuredLocation(from: dictionary["structured_location"]),
            alarms: EventKitDeserialization.alarms(from: dictionary["alarms"]),
            recurrenceRules: EventKitDeserialization.recurrenceRules(from: dictionary["recurrence_rules"])
        )
    }

    private func parseCreateEventDictionary(_ payloadJson: String) throws -> [String: Any] {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("calendar_identifier and title are required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        return try parseJSONObject(from: data)
    }

    private func requiredNonEmptyString(named key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) is required")
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("\(key) must not be empty")
        }
        return value
    }

    private func requiredEventDateRange(in dictionary: [String: Any]) throws -> (Date, Date) {
        guard let startDate = try requiredISO8601Date(named: "start_date", in: dictionary) else {
            throw EventKitProviderError.invalidArguments("start_date is required")
        }
        guard let endDate = try requiredISO8601Date(named: "end_date", in: dictionary) else {
            throw EventKitProviderError.invalidArguments("end_date is required")
        }

        if startDate > endDate {
            throw EventKitProviderError.invalidArguments("start_date must not be after end_date")
        }

        return (startDate, endDate)
    }

    private func optionalTimeZone(from dictionary: [String: Any]) throws -> TimeZone? {
        guard let timeZoneIdentifier = try EventKitDeserialization.optionalString(dictionary["time_zone"]) else {
            return nil
        }
        guard let resolved = TimeZone(identifier: timeZoneIdentifier) else {
            throw EventKitProviderError.invalidArguments("time_zone must be a valid timezone identifier")
        }
        return resolved
    }

    private func requiredISO8601Date(named key: String, in dictionary: [String: Any]) throws -> Date? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            throw EventKitProviderError.invalidArguments("\(key) is required")
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be an ISO8601 string")
        }

        guard let date = parseISO8601Date(value) else {
            throw EventKitProviderError.invalidArguments("\(key) must be a valid ISO8601 date-time")
        }

        return date
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }

        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        return internetDateTime.date(from: value)
    }
}

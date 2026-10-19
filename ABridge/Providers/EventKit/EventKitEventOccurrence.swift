@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    private enum OccurrenceTarget {
        case allDay(String)
        case instant(Date)
    }

    func eventReadyToMutate(_ event: EKEvent, occurrenceDate: String?) throws -> EKEvent {
        let identifier = eventIdentifier(of: event)
        if event.hasRecurrenceRules, occurrenceDate == nil {
            let calendars = try occurrenceCalendars(for: event)
            let hints = try upcomingOccurrenceStarts(identifier: identifier, calendars: calendars)
            throw EventKitProviderError.coded(
                code: "occurrence_required",
                message: occurrenceRequiredMessage(identifier: identifier, hints: hints)
            )
        }
        if let occurrenceDate {
            let calendars = try eventCalendars(calendarIdentifier: nil)
            return try resolveOccurrence(
                identifier: identifier,
                occurrenceDate: occurrenceDate,
                calendars: calendars
            )
        }
        return event
    }

    func eventIdentifier(of event: EKEvent) -> String {
        store.eventIdentifier(for: event) ?? event.calendarItemIdentifier
    }

    func resolveOccurrence(
        identifier: String,
        occurrenceDate: String,
        calendars: [EKCalendar]
    ) throws -> EKEvent {
        let target = try parseOccurrenceTarget(occurrenceDate)
        let window = occurrenceWindow(for: target)
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        let events = try store.fetchEvents(matching: predicate)
        let matches = events.filter { event in
            eventIdentifier(of: event) == identifier && occurrenceMatches(event, target)
        }
        guard let event = preferredOccurrence(matches, target: target) else {
            throw EventKitProviderError.coded(
                code: "not_found",
                message: "No occurrence of \(identifier) at \(occurrenceDate)"
            )
        }
        return event
    }

    func eventMutationSpan(in dictionary: [String: Any]) throws -> EKSpan {
        guard let value = dictionary["span"], !(value is NSNull) else {
            return .thisEvent
        }
        guard let span = value as? String else {
            throw EventKitProviderError.invalidArguments("span must be this_event or future_events")
        }
        switch span {
        case "this_event":
            return .thisEvent
        case "future_events":
            return .futureEvents
        default:
            throw EventKitProviderError.invalidArguments("span must be this_event or future_events")
        }
    }

    func optionalOccurrenceDate(_ dictionary: [String: Any]) throws -> String? {
        guard dictionary.keys.contains("occurrence_date"), !(dictionary["occurrence_date"] is NSNull) else {
            return nil
        }
        guard let value = dictionary["occurrence_date"] as? String else {
            throw EventKitProviderError.invalidArguments(
                "occurrence_date must be an offset date-time or an all-day YYYY-MM-DD"
            )
        }
        return value
    }

    func formattedOccurrenceStart(_ event: EKEvent) -> String {
        if event.isAllDay {
            return calendarDayString(of: event.startDate, timeZone: event.timeZone)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = event.timeZone ?? .current
        return formatter.string(from: event.startDate)
    }

    func eventInternetDate(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }
        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        return internetDateTime.date(from: value)
    }

    private func occurrenceCalendars(for event: EKEvent) throws -> [EKCalendar] {
        if let identifier = event.calendar?.calendarIdentifier,
           store.eventCalendars().contains(where: { $0.calendarIdentifier == identifier })
        {
            return try eventCalendars(calendarIdentifier: identifier)
        }
        return try eventCalendars(calendarIdentifier: nil)
    }

    private func upcomingOccurrenceStarts(identifier: String, calendars: [EKCalendar]) throws -> [String] {
        let now = Date()
        let end = now.addingTimeInterval(2 * 365 * 86400)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = try store.fetchEvents(matching: predicate)
        let matches = events
            .filter { eventIdentifier(of: $0) == identifier && $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
        var seen: Set<String> = []
        var hints: [String] = []
        for event in matches {
            let label = formattedOccurrenceStart(event)
            if seen.insert(label).inserted {
                hints.append(label)
            }
            if hints.count == 5 {
                break
            }
        }
        return hints
    }

    private func occurrenceRequiredMessage(identifier: String, hints: [String]) -> String {
        let span = "span is this_event (default) or future_events."
        if hints.isEmpty {
            return "occurrence_date is required for recurring event \(identifier). " +
                "No occurrence starts in the next 2 years. " +
                "Pass the start_date a list or search row showed. \(span)"
        }
        let listed = hints.joined(separator: ", ")
        return "occurrence_date is required for recurring event \(identifier). " +
            "Upcoming starts: \(listed). Pass one as occurrence_date. \(span)"
    }

    private func calendarDayString(of date: Date, timeZone: TimeZone?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func parseOccurrenceTarget(_ value: String) throws -> OccurrenceTarget {
        if isCalendarDay(value) {
            guard calendarDayIsValid(value) else {
                throw EventKitProviderError.invalidArguments(
                    "occurrence_date must be an offset date-time or an all-day YYYY-MM-DD"
                )
            }
            return .allDay(value)
        }
        guard let date = eventInternetDate(value) else {
            throw EventKitProviderError.invalidArguments(
                "occurrence_date must be an offset date-time or an all-day YYYY-MM-DD"
            )
        }
        return .instant(date)
    }

    private func isCalendarDay(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
            return false
        }
        return parts.allSatisfy { part in part.allSatisfy(\.isNumber) }
    }

    private func calendarDayIsValid(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return false
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.isValidDate
    }

    private func occurrenceWindow(for target: OccurrenceTarget) -> (start: Date, end: Date) {
        switch target {
        case let .allDay(day):
            let parts = day.split(separator: "-")
            var components = DateComponents()
            components.year = Int(parts[0])
            components.month = Int(parts[1])
            components.day = Int(parts[2])
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            let noon = calendar.date(from: components) ?? Date()
            return (noon.addingTimeInterval(-2 * 86400), noon.addingTimeInterval(3 * 86400))
        case let .instant(date):
            return (date.addingTimeInterval(-36 * 3600), date.addingTimeInterval(36 * 3600))
        }
    }

    private func occurrenceMatches(_ event: EKEvent, _ target: OccurrenceTarget) -> Bool {
        switch target {
        case let .allDay(day):
            guard event.isAllDay else { return false }
            return calendarDayString(of: event.startDate, timeZone: event.timeZone) == day
        case let .instant(date):
            return abs(event.startDate.timeIntervalSince(date)) < 1
        }
    }

    private func preferredOccurrence(_ events: [EKEvent], target: OccurrenceTarget) -> EKEvent? {
        switch target {
        case .allDay:
            events.min { $0.startDate < $1.startDate }
        case let .instant(date):
            events.min {
                abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date))
            }
        }
    }
}

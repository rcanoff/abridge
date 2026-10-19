@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    private struct DeleteEventArguments {
        let identifier: String?
        let title: String?
        let calendarIdentifier: String?
        let startDate: Date?
        let endDate: Date?
        let occurrenceDate: String?
        let span: EKSpan
    }

    func deleteEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseDeleteEventArguments(payloadJson)
            let event = try eventForDelete(arguments)
            let deletedIdentifier = eventIdentifier(of: event)
            try store.removeEvent(event, span: arguments.span, commit: true)

            let payload = try EventKitSerialization.jsonString(from: [
                "event_identifier": deletedIdentifier,
            ])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func eventForDelete(_ arguments: DeleteEventArguments) throws -> EKEvent {
        let event: EKEvent
        if let title = arguments.title {
            event = try eventMatchingTitle(
                title,
                calendarIdentifier: arguments.calendarIdentifier,
                start: arguments.startDate,
                end: arguments.endDate
            )
        } else {
            let identifier = arguments.identifier ?? ""
            guard let found = try store.fetchEvent(withIdentifier: identifier) else {
                throw EventKitProviderError.invalidArguments("Unknown event_identifier: \(identifier)")
            }
            event = found
        }
        return try eventReadyToMutate(event, occurrenceDate: arguments.occurrenceDate)
    }

    private func eventMatchingTitle(
        _ title: String,
        calendarIdentifier: String?,
        start: Date?,
        end: Date?
    ) throws -> EKEvent {
        let calendars = try eventCalendars(calendarIdentifier: calendarIdentifier)
        let bounds = titleSearchBounds(explicitStart: start, explicitEnd: end)
        if bounds.start > bounds.end {
            throw EventKitProviderError.invalidArguments("start_date must not be after end_date")
        }
        let predicate = store.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: calendars)
        let events = try store.fetchEvents(matching: predicate)
        let matches = events.filter { eventKitTitlesMatch($0.title, title) }
        var groups: [String: [EKEvent]] = [:]
        for event in matches {
            groups[eventIdentifier(of: event), default: []].append(event)
        }
        if groups.isEmpty {
            throw EventKitProviderError.coded(code: "not_found", message: "no event titled \"\(title)\"")
        }
        if groups.count > 1 {
            throw eventTitleAmbiguous(title, groups: groups)
        }
        guard let series = groups.values.first else {
            throw EventKitProviderError.coded(code: "not_found", message: "no event titled \"\(title)\"")
        }
        return series.min { $0.startDate < $1.startDate } ?? series[0]
    }

    private func eventTitleAmbiguous(_ title: String, groups: [String: [EKEvent]]) -> EventKitProviderError {
        let now = Date()
        let identifiers = groups.keys.sorted()
        let limit = 10
        let listed = identifiers.prefix(limit).map { identifier -> String in
            let series = groups[identifier] ?? []
            let calendar = series.first?.calendar?.title ?? ""
            let next = nextStartLabel(series, now: now)
            let recurring = series.contains(where: \.hasRecurrenceRules) ? "yes" : "no"
            return "\(identifier) in \(calendar), next \(next), recurring \(recurring)"
        }.joined(separator: "; ")
        let extra = identifiers.count - min(identifiers.count, limit)
        let suffix = extra > 0 ? "; and \(extra) more." : "."
        return .coded(
            code: "event_title_ambiguous",
            message: "\"\(title)\" matches more than one event. Candidates: \(listed)\(suffix)"
        )
    }

    private func nextStartLabel(_ events: [EKEvent], now: Date) -> String {
        let upcoming = events.filter { $0.startDate >= now }.min { $0.startDate < $1.startDate }
        let chosen = upcoming ?? events.max { $0.startDate < $1.startDate }
        guard let chosen else { return "" }
        return formattedOccurrenceStart(chosen)
    }

    private func titleSearchBounds(explicitStart: Date?, explicitEnd: Date?) -> (start: Date, end: Date) {
        let now = Date()
        let day: TimeInterval = 86400
        let defaultStart = now.addingTimeInterval(-365 * day)
        let defaultEnd = now.addingTimeInterval(2 * 365 * day)
        var start = explicitStart ?? defaultStart
        var end = explicitEnd ?? defaultEnd
        let maxSpan = TimeInterval(4 * 365 - 1) * day
        if explicitStart == nil, end.timeIntervalSince(start) > maxSpan {
            start = end.addingTimeInterval(-maxSpan)
        }
        if explicitEnd == nil, end.timeIntervalSince(start) > maxSpan {
            end = start.addingTimeInterval(maxSpan)
        }
        return (start, end)
    }

    private func parseDeleteEventArguments(_ payloadJson: String) throws -> DeleteEventArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }
        let dictionary = try parseJSONObject(from: data)
        let identifier = dictionary["event_identifier"] as? String
        let title = dictionary["event_title"] as? String
        if identifier != nil, title != nil {
            throw EventKitProviderError.invalidArguments(
                "Provide exactly one of event_identifier or event_title."
            )
        }
        let resolvedIdentifier = identifier ?? (title == nil
            ? SchemaTrustedPayload.requiredString(dictionary, "event_identifier")
            : nil)
        return try DeleteEventArguments(
            identifier: resolvedIdentifier,
            title: title,
            calendarIdentifier: optionalUntrimmedEventString(dictionary, key: "calendar_identifier"),
            startDate: optionalInternetDate(dictionary, key: "start_date"),
            endDate: optionalInternetDate(dictionary, key: "end_date"),
            occurrenceDate: optionalOccurrenceDate(dictionary),
            span: eventMutationSpan(in: dictionary)
        )
    }

    private func optionalUntrimmedEventString(_ dictionary: [String: Any], key: String) throws -> String? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be a string or null")
        }
        return value
    }

    private func optionalInternetDate(_ dictionary: [String: Any], key: String) throws -> Date? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be an ISO8601 string or null")
        }
        guard let date = eventInternetDate(value) else {
            throw EventKitProviderError.invalidArguments("\(key) must be a valid ISO8601 date-time")
        }
        return date
    }
}

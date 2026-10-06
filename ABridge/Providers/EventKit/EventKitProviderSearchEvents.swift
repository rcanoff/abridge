@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct SearchEventsArguments {
        let startDate: Date
        let endDate: Date
        let calendarIdentifier: String?
        let query: String
    }

    func searchEvents(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseSearchEventsArguments(payloadJson)
            let calendars = try eventCalendars(calendarIdentifier: arguments.calendarIdentifier)
            let predicate = store.predicateForEvents(
                withStart: arguments.startDate,
                end: arguments.endDate,
                calendars: calendars
            )
            let events = try store.fetchEvents(matching: predicate)
                .filter { matchesQuery($0, query: arguments.query) }
            let payloadObjects = events.map { serializedEventJSONObject(from: $0) }
            let payload = try EventKitSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func matchesQuery(_ event: EKEvent, query: String) -> Bool {
        let needle = query.lowercased()
        let candidates = [event.title, event.notes, event.location]
        return candidates.contains { field in
            guard let field else { return false }
            return field.lowercased().contains(needle)
        }
    }

    private func parseSearchEventsArguments(_ payloadJson: String) throws -> SearchEventsArguments {
        let dictionary: [String: Any]
        if payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dictionary = [:]
        } else {
            guard let data = payloadJson.data(using: .utf8) else {
                throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
            }
            dictionary = try parseJSONObject(from: data)
        }

        let startDate = try optionalISO8601DateArgument(named: "start_date", in: dictionary) ?? .distantPast
        let endDate = try optionalISO8601DateArgument(named: "end_date", in: dictionary) ?? .distantFuture

        if startDate > endDate {
            throw EventKitProviderError.invalidArguments("start_date must not be after end_date")
        }

        let calendarIdentifier = try optionalStringArgument(named: "calendar_identifier", in: dictionary)
        let query = try requiredNonEmptyStringArgument(named: "query", in: dictionary)

        return SearchEventsArguments(
            startDate: startDate,
            endDate: endDate,
            calendarIdentifier: calendarIdentifier,
            query: query
        )
    }

    private func optionalISO8601DateArgument(named key: String, in dictionary: [String: Any]) throws -> Date? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be an ISO8601 string or null")
        }

        guard let date = parseISO8601Date(value) else {
            throw EventKitProviderError.invalidArguments("\(key) must be a valid ISO8601 date-time")
        }

        return date
    }

    private func optionalStringArgument(named key: String, in dictionary: [String: Any]) throws -> String? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be a string or null")
        }

        return value
    }

    private func requiredNonEmptyStringArgument(named key: String, in dictionary: [String: Any]) throws -> String {
        // Schema owns required + non-empty.
        SchemaTrustedPayload.requiredString(dictionary, key)
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

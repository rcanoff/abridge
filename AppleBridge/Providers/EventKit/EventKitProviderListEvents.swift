@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct ListEventsArguments {
        let startDate: Date
        let endDate: Date
        let calendarIdentifier: String?
    }

    func listEvents(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseListEventsArguments(payloadJson)
            let calendars = try eventCalendars(calendarIdentifier: arguments.calendarIdentifier)
            let predicate = store.predicateForEvents(
                withStart: arguments.startDate,
                end: arguments.endDate,
                calendars: calendars
            )
            let events = try store.fetchEvents(matching: predicate)
            let payloadObjects = events.map { serializedEventJSONObject(from: $0) }
            let payload = try EventKitSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func parseListEventsArguments(_ payloadJson: String) throws -> ListEventsArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("start_date is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let startDate = try requiredISO8601DateArgument(named: "start_date", in: dictionary) else {
            throw EventKitProviderError.invalidArguments("start_date is required")
        }
        guard let endDate = try requiredISO8601DateArgument(named: "end_date", in: dictionary) else {
            throw EventKitProviderError.invalidArguments("end_date is required")
        }

        if startDate > endDate {
            throw EventKitProviderError.invalidArguments("start_date must not be after end_date")
        }

        let calendarIdentifier = try optionalStringArgument(named: "calendar_identifier", in: dictionary)

        return ListEventsArguments(
            startDate: startDate,
            endDate: endDate,
            calendarIdentifier: calendarIdentifier
        )
    }

    private func requiredISO8601DateArgument(named key: String, in dictionary: [String: Any]) throws -> Date? {
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

    private func optionalStringArgument(named key: String, in dictionary: [String: Any]) throws -> String? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be a string or null")
        }

        return value
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

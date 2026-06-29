@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct SetEventRecurrenceArguments {
        let eventIdentifier: String
        let recurrenceRules: [EKRecurrenceRule]
    }

    func setEventRecurrence(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseSetEventRecurrenceArguments(payloadJson)
            guard let event = try store.fetchEvent(withIdentifier: arguments.eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(arguments.eventIdentifier)"
                )
            }

            event.recurrenceRules = arguments.recurrenceRules
            try store.saveEvent(event, commit: true)

            let payload = try EventKitSerialization.jsonString(
                from: serializedEventJSONObject(from: event)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func parseSetEventRecurrenceArguments(_ payloadJson: String) throws -> SetEventRecurrenceArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("event_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let eventIdentifier = try parseEventIdentifierArguments(payloadJson)

        guard dictionary.keys.contains("recurrence_rules") else {
            throw EventKitProviderError.invalidArguments("recurrence_rules is required")
        }
        guard let recurrenceRules = try EventKitDeserialization.recurrenceRules(from: dictionary["recurrence_rules"])
        else {
            throw EventKitProviderError.invalidArguments("recurrence_rules must be an array")
        }

        return SetEventRecurrenceArguments(eventIdentifier: eventIdentifier, recurrenceRules: recurrenceRules)
    }
}

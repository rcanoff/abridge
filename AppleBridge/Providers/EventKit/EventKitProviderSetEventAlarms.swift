@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct SetEventAlarmsArguments {
        let eventIdentifier: String
        let alarms: [EKAlarm]
    }

    func setEventAlarms(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseSetEventAlarmsArguments(payloadJson)
            guard let event = try store.fetchEvent(withIdentifier: arguments.eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(arguments.eventIdentifier)"
                )
            }

            event.alarms = arguments.alarms
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

    private func parseSetEventAlarmsArguments(_ payloadJson: String) throws -> SetEventAlarmsArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("event_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let eventIdentifier = try parseEventIdentifierArguments(payloadJson)

        guard dictionary.keys.contains("alarms") else {
            throw EventKitProviderError.invalidArguments("alarms is required")
        }
        guard let alarms = try EventKitDeserialization.alarms(from: dictionary["alarms"]) else {
            throw EventKitProviderError.invalidArguments("alarms must be an array")
        }

        return SetEventAlarmsArguments(eventIdentifier: eventIdentifier, alarms: alarms)
    }
}

@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct MoveEventArguments {
        let eventIdentifier: String
        let calendarIdentifier: String
    }

    func moveEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseMoveEventArguments(payloadJson)
            guard let event = try store.fetchEvent(withIdentifier: arguments.eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(arguments.eventIdentifier)"
                )
            }

            let calendars = try eventCalendars(calendarIdentifier: arguments.calendarIdentifier)
            guard let calendar = calendars.first else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_identifier: \(arguments.calendarIdentifier)"
                )
            }

            event.calendar = calendar
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

    private func parseMoveEventArguments(_ payloadJson: String) throws -> MoveEventArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let eventIdentifier = try parseEventIdentifierArguments(payloadJson)

        let calendarIdentifier = SchemaTrustedPayload.requiredString(dictionary, "calendar_identifier")
        let trimmedCalendar = calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCalendar.isEmpty else {
            throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
        }

        return MoveEventArguments(eventIdentifier: eventIdentifier, calendarIdentifier: trimmedCalendar)
    }
}

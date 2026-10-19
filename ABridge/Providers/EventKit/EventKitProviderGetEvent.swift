@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func getEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let data = try eventPayloadData(payloadJson)
            let dictionary = try parseJSONObject(from: data)
            let eventIdentifier = SchemaTrustedPayload.requiredString(dictionary, "event_identifier")
            guard let fetched = try store.fetchEvent(withIdentifier: eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(eventIdentifier)"
                )
            }
            let event: EKEvent
            if let occurrenceDate = try optionalOccurrenceDate(dictionary) {
                let calendars = try eventCalendars(calendarIdentifier: nil)
                event = try resolveOccurrence(
                    identifier: self.eventIdentifier(of: fetched),
                    occurrenceDate: occurrenceDate,
                    calendars: calendars
                )
            } else {
                event = fetched
            }
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

    func parseEventIdentifierArguments(_ payloadJson: String) throws -> String {
        let dictionary = try parseJSONObject(from: eventPayloadData(payloadJson))
        // Required non-empty event_identifier is schema-owned (Rust).
        return SchemaTrustedPayload.requiredString(dictionary, "event_identifier")
    }

    private func eventPayloadData(_ payloadJson: String) throws -> Data {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }
        return data
    }
}

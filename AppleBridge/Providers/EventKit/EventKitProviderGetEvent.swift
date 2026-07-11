@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func getEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let eventIdentifier = try parseEventIdentifierArguments(payloadJson)
            guard let event = try store.fetchEvent(withIdentifier: eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(eventIdentifier)"
                )
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
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        // Required non-empty event_identifier is schema-owned (Rust).
        return SchemaTrustedPayload.requiredString(dictionary, "event_identifier")
    }
}

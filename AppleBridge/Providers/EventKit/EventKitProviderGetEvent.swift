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
                from: EventKitSerialization.eventJSONObject(from: event)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func parseEventIdentifierArguments(_ payloadJson: String) throws -> String {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("event_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let eventIdentifier = dictionary["event_identifier"] as? String else {
            throw EventKitProviderError.invalidArguments("event_identifier is required")
        }

        let trimmed = eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EventKitProviderError.invalidArguments("event_identifier must not be empty")
        }

        return trimmed
    }
}

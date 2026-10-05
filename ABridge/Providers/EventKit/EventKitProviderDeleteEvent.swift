@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func deleteEvent(payloadJson: String) -> ProviderResponse {
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

            let deletedIdentifier = store.eventIdentifier(for: event) ?? eventIdentifier
            try store.removeEvent(event, commit: true)

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
}

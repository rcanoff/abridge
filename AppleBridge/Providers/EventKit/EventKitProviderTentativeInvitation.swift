@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func tentativeInvitation(payloadJson: String) -> ProviderResponse {
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

            try store.tentativeEventInvitation(event)
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
}

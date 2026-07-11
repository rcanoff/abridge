@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func parseCalendarIdentifierArguments(_ payloadJson: String) throws -> String {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        return SchemaTrustedPayload.requiredString(dictionary, "calendar_identifier")
    }

    func deleteList(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let calendarIdentifier = try parseCalendarIdentifierArguments(payloadJson)
            let calendars = try reminderCalendars(calendarIdentifier: calendarIdentifier)
            guard let calendar = calendars.first else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_identifier: \(calendarIdentifier)"
                )
            }

            try store.removeCalendar(calendar, commit: true)

            let payload = try EventKitSerialization.jsonString(from: [
                "calendar_identifier": calendarIdentifier,
            ])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}

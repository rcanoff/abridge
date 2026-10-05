@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func deleteCalendar(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let calendarIdentifier = try parseCalendarIdentifierArguments(payloadJson)
            let calendars = try eventCalendars(calendarIdentifier: calendarIdentifier)
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

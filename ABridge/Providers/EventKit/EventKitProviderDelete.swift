@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func deleteReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let reminderID = try parseReminderIDArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_item_identifier: \(reminderID)"
                )
            }

            let calendarItemIdentifier = reminder.calendarItemIdentifier
            try store.removeReminder(reminder, commit: true)

            let payload = try EventKitSerialization.jsonString(from: [
                "calendar_item_identifier": calendarItemIdentifier,
            ])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}

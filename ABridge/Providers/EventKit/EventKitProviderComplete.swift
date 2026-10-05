@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func completeReminder(payloadJson: String) -> ProviderResponse {
        setReminderCompletion(payloadJson: payloadJson, isCompleted: true)
    }

    func uncompleteReminder(payloadJson: String) -> ProviderResponse {
        setReminderCompletion(payloadJson: payloadJson, isCompleted: false)
    }

    /// Sets `EKReminder.isCompleted` only. EventKit automatically manages `completionDate`
    /// when `isCompleted` changes (Apple docs). After save, re-fetches so the response matches
    /// the store — for recurring reminders, completing advances the series and the obtainable
    /// item is typically the next incomplete occurrence.
    private func setReminderCompletion(payloadJson: String, isCompleted: Bool) -> ProviderResponse {
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

            let hadRecurrenceRules = !(reminder.recurrenceRules ?? []).isEmpty

            // EventKit: setting isCompleted adjusts completionDate; do not invent completionDate.
            reminder.isCompleted = isCompleted
            try store.saveReminder(reminder, commit: true)

            guard let saved = try store.fetchReminder(withIdentifier: reminderID) else {
                return errorResponse(
                    code: "eventkit_error",
                    message: "Reminder was not found after save (calendar_item_identifier: \(reminderID))"
                )
            }

            if isCompleted, !saved.isCompleted, !hadRecurrenceRules {
                return errorResponse(
                    code: "eventkit_error",
                    message: "EventKit did not mark the reminder completed after save"
                )
            }

            let payload = try EventKitSerialization.jsonString(
                from: EventKitSerialization.reminderJSONObject(from: saved)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}

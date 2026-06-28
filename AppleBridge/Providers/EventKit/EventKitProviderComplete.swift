@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func completeReminder(payloadJson: String) -> ProviderResponse {
        setReminderCompletion(payloadJson: payloadJson, isCompleted: true)
    }

    func uncompleteReminder(payloadJson: String) -> ProviderResponse {
        setReminderCompletion(payloadJson: payloadJson, isCompleted: false)
    }

    private func setReminderCompletion(payloadJson: String, isCompleted: Bool) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let reminderID = try parseReminderIDArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown reminder_id: \(reminderID)"
                )
            }

            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? Date() : nil
            try store.saveReminder(reminder, commit: true)

            let payload = try EventKitSerialization.jsonString(
                from: EventKitSerialization.reminderJSONObject(from: reminder)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}

@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct SetReminderRecurrenceArguments {
        let reminderID: String
        let recurrenceRules: [EKRecurrenceRule]
    }

    func setReminderRecurrence(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseSetReminderRecurrenceArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: arguments.reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_item_identifier: \(arguments.reminderID)"
                )
            }

            reminder.recurrenceRules = arguments.recurrenceRules
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

    private func parseSetReminderRecurrenceArguments(_ payloadJson: String) throws -> SetReminderRecurrenceArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let reminderID = try parseReminderIDArguments(payloadJson)

        let rulesRaw = SchemaTrustedPayload.requiredArray(dictionary, "recurrence_rules")
        let recurrenceRules = try EventKitDeserialization.recurrenceRules(from: rulesRaw) ?? []

        return SetReminderRecurrenceArguments(reminderID: reminderID, recurrenceRules: recurrenceRules)
    }
}

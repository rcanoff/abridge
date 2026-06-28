@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct SetReminderAlarmsArguments {
        let reminderID: String
        let alarms: [EKAlarm]
    }

    func setReminderAlarms(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseSetReminderAlarmsArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: arguments.reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown reminder_id: \(arguments.reminderID)"
                )
            }

            reminder.alarms = arguments.alarms
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

    private func parseSetReminderAlarmsArguments(_ payloadJson: String) throws -> SetReminderAlarmsArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("reminder_id is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let reminderID = try parseReminderIDArguments(payloadJson)

        guard dictionary.keys.contains("alarms") else {
            throw EventKitProviderError.invalidArguments("alarms is required")
        }
        guard let alarms = try EventKitDeserialization.alarms(from: dictionary["alarms"]) else {
            throw EventKitProviderError.invalidArguments("alarms must be an array")
        }

        return SetReminderAlarmsArguments(reminderID: reminderID, alarms: alarms)
    }
}

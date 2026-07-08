@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct MoveReminderArguments {
        let reminderID: String
        let calendarIdentifier: String
    }

    func moveReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseMoveReminderArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: arguments.reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_item_identifier: \(arguments.reminderID)"
                )
            }

            let calendars = try reminderCalendars(calendarIdentifier: arguments.calendarIdentifier)
            guard let calendar = calendars.first else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_identifier: \(arguments.calendarIdentifier)"
                )
            }

            reminder.calendar = calendar
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

    private func parseMoveReminderArguments(_ payloadJson: String) throws -> MoveReminderArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("calendar_item_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let reminderID = try parseReminderIDArguments(payloadJson)

        guard let calendarIdentifier = dictionary["calendar_identifier"] as? String else {
            throw EventKitProviderError.invalidArguments("calendar_identifier is required")
        }
        let trimmedCalendar = calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCalendar.isEmpty else {
            throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
        }

        return MoveReminderArguments(reminderID: reminderID, calendarIdentifier: trimmedCalendar)
    }
}

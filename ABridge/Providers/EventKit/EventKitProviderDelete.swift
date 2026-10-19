@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    private struct DeleteReminderArguments {
        let identifier: String?
        let title: String?
        let calendarIdentifier: String?
    }

    func deleteReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseDeleteReminderArguments(payloadJson)
            let reminder: EKReminder
            if let title = arguments.title {
                reminder = try reminderMatchingTitle(title, calendarIdentifier: arguments.calendarIdentifier)
            } else {
                let reminderID = arguments.identifier ?? ""
                guard let found = try store.fetchReminder(withIdentifier: reminderID) else {
                    return errorResponse(
                        code: "invalid_arguments",
                        message: "Unknown calendar_item_identifier: \(reminderID)"
                    )
                }
                reminder = found
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

    func eventKitTitlesMatch(_ stored: String?, _ requested: String) -> Bool {
        guard let stored else { return false }
        return stored.compare(requested, options: [.caseInsensitive]) == .orderedSame
    }

    private func parseDeleteReminderArguments(_ payloadJson: String) throws -> DeleteReminderArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let identifier = dictionary["calendar_item_identifier"] as? String
        let title = dictionary["reminder_title"] as? String
        if identifier != nil, title != nil {
            throw EventKitProviderError.invalidArguments(
                "Provide exactly one of calendar_item_identifier or reminder_title."
            )
        }
        if identifier == nil, title == nil {
            return DeleteReminderArguments(
                identifier: SchemaTrustedPayload.requiredString(dictionary, "calendar_item_identifier"),
                title: nil,
                calendarIdentifier: nil
            )
        }

        return try DeleteReminderArguments(
            identifier: identifier,
            title: title,
            calendarIdentifier: optionalUntrimmedString(dictionary, key: "calendar_identifier")
        )
    }

    private func reminderMatchingTitle(_ title: String, calendarIdentifier: String?) throws -> EKReminder {
        let calendars = try reminderCalendars(calendarIdentifier: calendarIdentifier)
        let predicate = store.predicateForReminders(in: calendars)
        let reminders = try store.fetchReminders(matching: predicate)
        let matches = reminders.filter { eventKitTitlesMatch($0.title, title) }
        if matches.isEmpty {
            throw EventKitProviderError.coded(code: "not_found", message: "no reminder titled \"\(title)\"")
        }
        if matches.count == 1, let match = matches.first {
            return match
        }
        throw reminderTitleAmbiguous(title, matches: matches)
    }

    private func reminderTitleAmbiguous(_ title: String, matches: [EKReminder]) -> EventKitProviderError {
        let sorted = matches.sorted { lhs, rhs in
            let leftList = lhs.calendar?.title ?? ""
            let rightList = rhs.calendar?.title ?? ""
            if leftList != rightList {
                return leftList < rightList
            }
            return lhs.calendarItemIdentifier < rhs.calendarItemIdentifier
        }
        let limit = 10
        let listed = sorted.prefix(limit).map(reminderCandidate).joined(separator: "; ")
        let extra = sorted.count - min(sorted.count, limit)
        let suffix = extra > 0 ? "; and \(extra) more." : "."
        return .coded(
            code: "reminder_title_ambiguous",
            message: "\"\(title)\" matches more than one reminder. Candidates: \(listed)\(suffix)"
        )
    }

    private func reminderCandidate(_ reminder: EKReminder) -> String {
        let list = reminder.calendar?.title ?? ""
        let completed = reminder.isCompleted ? "true" : "false"
        let identifier = reminder.calendarItemIdentifier
        if let due = reminderDueLabel(reminder) {
            return "\(identifier) in \(list), due \(due), completed \(completed)"
        }
        return "\(identifier) in \(list), completed \(completed)"
    }

    private func reminderDueLabel(_ reminder: EKReminder) -> String? {
        guard let components = reminder.dueDateComponents,
              let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        let date = String(format: "%04d-%02d-%02d", year, month, day)
        guard components.hour != nil || components.minute != nil else {
            return date
        }
        if let zone = components.timeZone, let instant = components.date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = zone
            return formatter.string(from: instant)
        }
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        return String(format: "%@T%02d:%02d:%02d", date, hour, minute, second)
    }

    private func optionalUntrimmedString(_ dictionary: [String: Any], key: String) throws -> String? {
        guard dictionary.keys.contains(key), !(dictionary[key] is NSNull) else {
            return nil
        }
        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be a string or null")
        }
        return value
    }
}

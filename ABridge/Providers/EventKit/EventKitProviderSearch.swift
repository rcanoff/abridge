@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    enum ReminderCompletionStatus: String {
        case incomplete
        case completed
        case all
    }

    /// Arguments map 1:1 onto EventKit reminder predicates (no post-fetch filtering).
    ///
    /// - `incomplete` → `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)`
    /// - `completed` → `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)`
    /// - `all` → `predicateForReminders(in:)` (EventKit has no date window for this API)
    struct SearchRemindersArguments {
        let calendarIdentifier: String?
        let completionStatus: ReminderCompletionStatus
        let dueDateStarting: Date?
        let dueDateEnding: Date?
        let completionDateStarting: Date?
        let completionDateEnding: Date?
    }

    func searchReminders(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseSearchRemindersArguments(payloadJson)
            let calendars = try reminderCalendars(calendarIdentifier: arguments.calendarIdentifier)
            let predicate = searchPredicate(for: arguments, calendars: calendars)
            let reminders = try store.fetchReminders(matching: predicate)
            let payloadObjects = reminders.map(EventKitSerialization.reminderJSONObject)
            let payload = try EventKitSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func reminderCalendars(calendarIdentifier: String?) throws -> [EKCalendar] {
        let calendars = store.reminderCalendars()
        if let calendarIdentifier {
            guard let calendar = calendars.first(where: { $0.calendarIdentifier == calendarIdentifier }) else {
                throw EventKitProviderError.invalidArguments("Unknown calendar_identifier: \(calendarIdentifier)")
            }
            return [calendar]
        }
        return calendars
    }

    func eventCalendars(calendarIdentifier: String?) throws -> [EKCalendar] {
        let calendars = store.eventCalendars()
        if let calendarIdentifier {
            guard let calendar = calendars.first(where: { $0.calendarIdentifier == calendarIdentifier }) else {
                throw EventKitProviderError.invalidArguments("Unknown calendar_identifier: \(calendarIdentifier)")
            }
            return [calendar]
        }
        return calendars
    }

    private func searchPredicate(
        for arguments: SearchRemindersArguments,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        switch arguments.completionStatus {
        case .incomplete:
            store.predicateForIncompleteReminders(
                withDueDateStarting: arguments.dueDateStarting,
                ending: arguments.dueDateEnding,
                calendars: calendars
            )
        case .completed:
            store.predicateForCompletedReminders(
                withCompletionDateStarting: arguments.completionDateStarting,
                ending: arguments.completionDateEnding,
                calendars: calendars
            )
        case .all:
            store.predicateForReminders(in: calendars)
        }
    }

    private func parseSearchRemindersArguments(_ payloadJson: String) throws -> SearchRemindersArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchRemindersArguments(
                calendarIdentifier: nil,
                completionStatus: .all,
                dueDateStarting: nil,
                dueDateEnding: nil,
                completionDateStarting: nil,
                completionDateEnding: nil
            )
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let calendarIdentifier = try optionalStringArgument(named: "calendar_identifier", in: dictionary)
        let completionStatus = try parseCompletionStatusArgument(in: dictionary)
        let dates = try parseSearchDateArguments(in: dictionary)
        try validateDateArgsForCompletionStatus(
            completionStatus: completionStatus,
            dueDateStarting: dates.dueStarting,
            dueDateEnding: dates.dueEnding,
            completionDateStarting: dates.completionStarting,
            completionDateEnding: dates.completionEnding
        )

        return SearchRemindersArguments(
            calendarIdentifier: calendarIdentifier,
            completionStatus: completionStatus,
            dueDateStarting: dates.dueStarting,
            dueDateEnding: dates.dueEnding,
            completionDateStarting: dates.completionStarting,
            completionDateEnding: dates.completionEnding
        )
    }

    private struct SearchDateArguments {
        let dueStarting: Date?
        let dueEnding: Date?
        let completionStarting: Date?
        let completionEnding: Date?
    }

    private func parseSearchDateArguments(in dictionary: [String: Any]) throws -> SearchDateArguments {
        let dueStarting = try optionalISO8601DateArgument(named: "due_date_starting", in: dictionary)
        let dueEnding = try optionalISO8601DateArgument(named: "due_date_ending", in: dictionary)
        let completionStarting = try optionalISO8601DateArgument(
            named: "completion_date_starting",
            in: dictionary
        )
        let completionEnding = try optionalISO8601DateArgument(
            named: "completion_date_ending",
            in: dictionary
        )
        if let dueStarting, let dueEnding, dueStarting > dueEnding {
            throw EventKitProviderError.invalidArguments(
                "due_date_starting must not be after due_date_ending"
            )
        }
        if let completionStarting, let completionEnding, completionStarting > completionEnding {
            throw EventKitProviderError.invalidArguments(
                "completion_date_starting must not be after completion_date_ending"
            )
        }
        return SearchDateArguments(
            dueStarting: dueStarting,
            dueEnding: dueEnding,
            completionStarting: completionStarting,
            completionEnding: completionEnding
        )
    }

    private func validateDateArgsForCompletionStatus(
        completionStatus: ReminderCompletionStatus,
        dueDateStarting: Date?,
        dueDateEnding: Date?,
        completionDateStarting: Date?,
        completionDateEnding: Date?
    ) throws {
        let hasDueDates = dueDateStarting != nil || dueDateEnding != nil
        let hasCompletionDates = completionDateStarting != nil || completionDateEnding != nil

        switch completionStatus {
        case .incomplete:
            if hasCompletionDates {
                throw EventKitProviderError.invalidArguments(
                    "completion_date_* apply only with completion_status completed "
                        + "(EventKit withCompletionDateStarting/ending)"
                )
            }
        case .completed:
            if hasDueDates {
                throw EventKitProviderError.invalidArguments(
                    "due_date_* apply only with completion_status incomplete "
                        + "(EventKit withDueDateStarting/ending)"
                )
            }
        case .all:
            if hasDueDates || hasCompletionDates {
                throw EventKitProviderError.invalidArguments(
                    "completion_status all uses predicateForReminders(in:) with no date window; "
                        + "omit due_date_* and completion_date_*"
                )
            }
        }
    }

    private func parseCompletionStatusArgument(in dictionary: [String: Any]) throws -> ReminderCompletionStatus {
        guard dictionary.keys.contains("completion_status") else {
            return .all
        }

        if dictionary["completion_status"] is NSNull {
            return .all
        }

        guard let rawValue = dictionary["completion_status"] as? String else {
            return .all // schema type; offline default
        }

        guard let status = ReminderCompletionStatus(rawValue: rawValue) else {
            throw EventKitProviderError.invalidArguments(
                "completion_status must be one of: incomplete, completed, all"
            )
        }

        return status
    }

    private func optionalStringArgument(named key: String, in dictionary: [String: Any]) throws -> String? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be a string or null")
        }

        return value
    }

    private func optionalISO8601DateArgument(named key: String, in dictionary: [String: Any]) throws -> Date? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw EventKitProviderError.invalidArguments("\(key) must be an ISO8601 string or null")
        }

        guard let date = Self.parseISO8601Date(value) else {
            throw EventKitProviderError.invalidArguments("\(key) must be a valid ISO8601 date-time")
        }

        return date
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }

        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        return internetDateTime.date(from: value)
    }
}

@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    enum ReminderCompletionStatus: String {
        case incomplete
        case completed
        case all
    }

    struct SearchRemindersArguments {
        let calendarIdentifier: String?
        let completionStatus: ReminderCompletionStatus
        let dueDateStart: Date?
        let dueDateEnd: Date?
    }

    func searchReminders(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseSearchRemindersArguments(payloadJson)
            let calendars = try reminderCalendars(calendarIdentifier: arguments.calendarIdentifier)
            let predicate = searchPredicate(for: arguments, calendars: calendars)
            var reminders = try store.fetchReminders(matching: predicate)
            reminders = applyPostFetchFilters(to: reminders, arguments: arguments)
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

    func eventCalendars(calendarIdentifier: String) throws -> [EKCalendar] {
        let calendars = store.eventCalendars()
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == calendarIdentifier }) else {
            throw EventKitProviderError.invalidArguments("Unknown calendar_identifier: \(calendarIdentifier)")
        }
        return [calendar]
    }

    private func searchPredicate(
        for arguments: SearchRemindersArguments,
        calendars: [EKCalendar]
    ) -> NSPredicate {
        let hasDueDates = arguments.dueDateStart != nil || arguments.dueDateEnd != nil

        switch arguments.completionStatus {
        case .incomplete:
            return store.predicateForIncompleteReminders(
                withDueDateStarting: hasDueDates ? arguments.dueDateStart : nil,
                ending: hasDueDates ? arguments.dueDateEnd : nil,
                calendars: calendars
            )
        case .completed:
            return store.predicateForCompletedReminders(
                withCompletionDateStarting: nil,
                ending: nil,
                calendars: calendars
            )
        case .all:
            return store.predicateForReminders(in: calendars)
        }
    }

    private func applyPostFetchFilters(
        to reminders: [EKReminder],
        arguments: SearchRemindersArguments
    ) -> [EKReminder] {
        var filtered = reminders

        let hasDueDates = arguments.dueDateStart != nil || arguments.dueDateEnd != nil
        if hasDueDates, arguments.completionStatus == .all || arguments.completionStatus == .completed {
            filtered = filtered.filter { reminder in
                guard let dueDate = dueDate(from: reminder.dueDateComponents) else {
                    return false
                }
                if let start = arguments.dueDateStart, dueDate < start {
                    return false
                }
                if let end = arguments.dueDateEnd, dueDate > end {
                    return false
                }
                return true
            }
        }

        return filtered
    }

    private func dueDate(from components: DateComponents?) -> Date? {
        guard let components else {
            return nil
        }
        return Calendar.current.date(from: components)
    }

    private func parseSearchRemindersArguments(_ payloadJson: String) throws -> SearchRemindersArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchRemindersArguments(
                calendarIdentifier: nil,
                completionStatus: .all,
                dueDateStart: nil,
                dueDateEnd: nil
            )
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let calendarIdentifier = try optionalStringArgument(named: "calendar_identifier", in: dictionary)
        let completionStatus = try parseCompletionStatusArgument(in: dictionary)
        let dueDateStart = try optionalISO8601DateArgument(named: "due_date_start", in: dictionary)
        let dueDateEnd = try optionalISO8601DateArgument(named: "due_date_end", in: dictionary)

        if let dueDateStart, let dueDateEnd, dueDateStart > dueDateEnd {
            throw EventKitProviderError.invalidArguments("due_date_start must not be after due_date_end")
        }

        return SearchRemindersArguments(
            calendarIdentifier: calendarIdentifier,
            completionStatus: completionStatus,
            dueDateStart: dueDateStart,
            dueDateEnd: dueDateEnd
        )
    }

    private func parseCompletionStatusArgument(in dictionary: [String: Any]) throws -> ReminderCompletionStatus {
        guard dictionary.keys.contains("completion_status") else {
            return .all
        }

        if dictionary["completion_status"] is NSNull {
            return .all
        }

        guard let rawValue = dictionary["completion_status"] as? String else {
            throw EventKitProviderError.invalidArguments("completion_status must be a string")
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

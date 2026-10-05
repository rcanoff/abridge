@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct CreateReminderArguments {
        let calendarIdentifier: String
        let title: String
        let notes: String?
        let location: String?
        let url: URL?
        let priority: Int?
        let dueDateComponents: DateComponents?
        let startDateComponents: DateComponents?
        let timeZone: TimeZone?
        let isCompleted: Bool?
        let completionDate: Date?
        let alarms: [EKAlarm]?
        let recurrenceRules: [EKRecurrenceRule]?
    }

    func createReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseCreateReminderArguments(payloadJson)
            let calendars = try reminderCalendars(calendarIdentifier: arguments.calendarIdentifier)
            guard let calendar = calendars.first else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown calendar_identifier: \(arguments.calendarIdentifier)"
                )
            }

            let reminder = store.makeReminder()
            try applyCreateArguments(arguments, to: reminder, calendar: calendar)
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

    private func applyCreateArguments(
        _ arguments: CreateReminderArguments,
        to reminder: EKReminder,
        calendar: EKCalendar
    ) throws {
        reminder.calendar = calendar
        reminder.title = arguments.title
        applyOptionalStringFields(from: arguments, to: reminder)
        try applyOptionalPriority(from: arguments, to: reminder)
        applyOptionalDateFields(from: arguments, to: reminder)
        applyOptionalCollectionFields(from: arguments, to: reminder)
    }

    private func applyOptionalStringFields(
        from arguments: CreateReminderArguments,
        to reminder: EKReminder
    ) {
        if let notes = arguments.notes { reminder.notes = notes }
        if let location = arguments.location { reminder.location = location }
        if let url = arguments.url { reminder.url = url }
        if let timeZone = arguments.timeZone { reminder.timeZone = timeZone }
    }

    private func applyOptionalPriority(
        from arguments: CreateReminderArguments,
        to reminder: EKReminder
    ) throws {
        // Priority range 0...9 is schema-owned (Rust inputSchema minimum/maximum).
        if let priority = arguments.priority {
            reminder.priority = priority
        }
    }

    private func applyOptionalDateFields(
        from arguments: CreateReminderArguments,
        to reminder: EKReminder
    ) {
        if let dueDateComponents = arguments.dueDateComponents {
            reminder.dueDateComponents = dueDateComponents
        }
        if let startDateComponents = arguments.startDateComponents {
            reminder.startDateComponents = startDateComponents
        }
        if let isCompleted = arguments.isCompleted { reminder.isCompleted = isCompleted }
        if let completionDate = arguments.completionDate { reminder.completionDate = completionDate }
    }

    private func applyOptionalCollectionFields(
        from arguments: CreateReminderArguments,
        to reminder: EKReminder
    ) {
        if let alarms = arguments.alarms { reminder.alarms = alarms }
        if let recurrenceRules = arguments.recurrenceRules { reminder.recurrenceRules = recurrenceRules }
    }

    private func parseCreateReminderArguments(_ payloadJson: String) throws -> CreateReminderArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        // Required non-empty calendar_identifier / title are schema-owned (Rust).
        let calendarIdentifier = SchemaTrustedPayload.requiredString(dictionary, "calendar_identifier")
        let title = SchemaTrustedPayload.requiredString(dictionary, "title")

        let timeZone: TimeZone?
        if let timeZoneIdentifier = try EventKitDeserialization.optionalString(dictionary["time_zone"]) {
            guard let resolved = TimeZone(identifier: timeZoneIdentifier) else {
                throw EventKitProviderError.invalidArguments("time_zone must be a valid timezone identifier")
            }
            timeZone = resolved
        } else {
            timeZone = nil
        }

        return try CreateReminderArguments(
            calendarIdentifier: calendarIdentifier,
            title: title,
            notes: EventKitDeserialization.optionalString(dictionary["notes"]),
            location: EventKitDeserialization.optionalString(dictionary["location"]),
            url: EventKitDeserialization.optionalURL(dictionary["url"]),
            priority: EventKitDeserialization.optionalInt(dictionary["priority"]),
            dueDateComponents: EventKitDeserialization.dateComponents(from: dictionary["due_date_components"]),
            startDateComponents: EventKitDeserialization.dateComponents(from: dictionary["start_date_components"]),
            timeZone: timeZone,
            isCompleted: EventKitDeserialization.optionalBool(dictionary["is_completed"]),
            completionDate: EventKitDeserialization.optionalISO8601Date(dictionary["completion_date"]),
            alarms: EventKitDeserialization.alarms(from: dictionary["alarms"]),
            recurrenceRules: EventKitDeserialization.recurrenceRules(from: dictionary["recurrence_rules"])
        )
    }
}

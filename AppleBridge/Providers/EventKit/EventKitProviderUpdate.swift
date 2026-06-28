@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct UpdateReminderArguments {
        let reminderID: String
        let calendarIdentifier: OptionalField<String>
        let title: OptionalField<String>
        let notes: OptionalField<String>
        let location: OptionalField<String>
        let url: OptionalField<URL>
        let priority: OptionalField<Int>
        let dueDateComponents: OptionalField<DateComponents>
        let startDateComponents: OptionalField<DateComponents>
        let timeZone: OptionalField<TimeZone>
        let isCompleted: OptionalField<Bool>
        let completionDate: OptionalField<Date>
        let alarms: OptionalField<[EKAlarm]>
        let recurrenceRules: OptionalField<[EKRecurrenceRule]>
    }

    func updateReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseUpdateReminderArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: arguments.reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown reminder_id: \(arguments.reminderID)"
                )
            }

            try applyUpdateArguments(arguments, to: reminder)
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

    private func applyUpdateArguments(_ arguments: UpdateReminderArguments, to reminder: EKReminder) throws {
        try applyOptionalCalendarIdentifier(from: arguments, to: reminder)
        try applyOptionalTitle(from: arguments, to: reminder)
        applyOptionalStringFields(from: arguments, to: reminder)
        try applyOptionalPriority(from: arguments, to: reminder)
        try applyOptionalDateFields(from: arguments, to: reminder)
        applyOptionalCollectionFields(from: arguments, to: reminder)
    }

    private func applyOptionalCalendarIdentifier(
        from arguments: UpdateReminderArguments,
        to reminder: EKReminder
    ) throws {
        switch arguments.calendarIdentifier {
        case .absent:
            return
        case let .present(calendarIdentifier):
            guard let calendarIdentifier else {
                throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
            }
            guard !calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
            }
            let calendars = try reminderCalendars(calendarIdentifier: calendarIdentifier)
            guard let calendar = calendars.first else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown calendar_identifier: \(calendarIdentifier)"
                )
            }
            reminder.calendar = calendar
        }
    }

    private func applyOptionalTitle(from arguments: UpdateReminderArguments, to reminder: EKReminder) throws {
        switch arguments.title {
        case .absent:
            return
        case let .present(title):
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EventKitProviderError.invalidArguments("title must not be empty")
            }
            reminder.title = title
        }
    }

    private func applyOptionalStringFields(from arguments: UpdateReminderArguments, to reminder: EKReminder) {
        switch arguments.notes {
        case .absent:
            break
        case let .present(notes):
            reminder.notes = notes
        }

        switch arguments.location {
        case .absent:
            break
        case let .present(location):
            reminder.location = location
        }

        switch arguments.url {
        case .absent:
            break
        case let .present(url):
            reminder.url = url
        }

        switch arguments.timeZone {
        case .absent:
            break
        case let .present(timeZone):
            reminder.timeZone = timeZone
        }
    }

    private func applyOptionalPriority(
        from arguments: UpdateReminderArguments,
        to reminder: EKReminder
    ) throws {
        switch arguments.priority {
        case .absent:
            return
        case let .present(priority):
            guard let priority else {
                throw EventKitProviderError.invalidArguments("priority must be between 0 and 9")
            }
            guard (0 ... 9).contains(priority) else {
                throw EventKitProviderError.invalidArguments("priority must be between 0 and 9")
            }
            reminder.priority = priority
        }
    }

    private func applyOptionalDateFields(from arguments: UpdateReminderArguments, to reminder: EKReminder) throws {
        switch arguments.dueDateComponents {
        case .absent:
            break
        case let .present(dueDateComponents):
            reminder.dueDateComponents = dueDateComponents
        }

        switch arguments.startDateComponents {
        case .absent:
            break
        case let .present(startDateComponents):
            reminder.startDateComponents = startDateComponents
        }

        switch arguments.isCompleted {
        case .absent:
            break
        case let .present(isCompleted):
            guard let isCompleted else {
                throw EventKitProviderError.invalidArguments("is_completed must be a boolean")
            }
            reminder.isCompleted = isCompleted
        }

        switch arguments.completionDate {
        case .absent:
            break
        case let .present(completionDate):
            reminder.completionDate = completionDate
        }
    }

    private func applyOptionalCollectionFields(from arguments: UpdateReminderArguments, to reminder: EKReminder) {
        switch arguments.alarms {
        case .absent:
            break
        case let .present(alarms):
            reminder.alarms = alarms
        }

        switch arguments.recurrenceRules {
        case .absent:
            break
        case let .present(recurrenceRules):
            reminder.recurrenceRules = recurrenceRules
        }
    }

    private func parseUpdateReminderArguments(_ payloadJson: String) throws -> UpdateReminderArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("reminder_id is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let reminderID = try parseReminderIDArguments(payloadJson)

        let timeZone: OptionalField<TimeZone>
        switch try EventKitDeserialization.optionalPresentString(dictionary, key: "time_zone") {
        case .absent:
            timeZone = .absent
        case let .present(timeZoneIdentifier):
            if let timeZoneIdentifier {
                guard let resolved = TimeZone(identifier: timeZoneIdentifier) else {
                    throw EventKitProviderError.invalidArguments("time_zone must be a valid timezone identifier")
                }
                timeZone = .present(resolved)
            } else {
                timeZone = .present(nil)
            }
        }

        return try UpdateReminderArguments(
            reminderID: reminderID,
            calendarIdentifier: EventKitDeserialization.optionalPresentString(dictionary, key: "calendar_identifier"),
            title: EventKitDeserialization.optionalPresentString(dictionary, key: "title"),
            notes: EventKitDeserialization.optionalPresentString(dictionary, key: "notes"),
            location: EventKitDeserialization.optionalPresentString(dictionary, key: "location"),
            url: EventKitDeserialization.optionalPresentURL(dictionary, key: "url"),
            priority: EventKitDeserialization.optionalPresentInt(dictionary, key: "priority"),
            dueDateComponents: EventKitDeserialization.optionalPresentDateComponents(
                dictionary,
                key: "due_date_components"
            ),
            startDateComponents: EventKitDeserialization.optionalPresentDateComponents(
                dictionary,
                key: "start_date_components"
            ),
            timeZone: timeZone,
            isCompleted: EventKitDeserialization.optionalPresentBool(dictionary, key: "is_completed"),
            completionDate: EventKitDeserialization.optionalPresentISO8601Date(dictionary, key: "completion_date"),
            alarms: EventKitDeserialization.optionalPresentAlarms(dictionary, key: "alarms"),
            recurrenceRules: EventKitDeserialization.optionalPresentRecurrenceRules(
                dictionary,
                key: "recurrence_rules"
            )
        )
    }
}

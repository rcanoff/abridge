import EventKit
import Foundation

protocol ReminderRepresentable {
    var calendarItemIdentifier: String { get }
    var reminderListID: String? { get }
    var reminderTitle: String? { get }
    var isCompleted: Bool { get }
    var dueDateComponents: DateComponents? { get }
    var reminderNotes: String? { get }
}

extension EKReminder: ReminderRepresentable {
    var reminderListID: String? {
        calendar?.calendarIdentifier
    }

    var reminderTitle: String? {
        title
    }

    var reminderNotes: String? {
        notes
    }
}

enum EventKitReminderMapping {
    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func listDictionary(from calendar: EKCalendar) -> [String: Any] {
        [
            "id": calendar.calendarIdentifier,
            "title": calendar.title,
            "source": calendar.source.title,
        ]
    }

    static func reminderDictionary(from reminder: some ReminderRepresentable) -> [String: Any] {
        var payload: [String: Any] = [
            "id": reminder.calendarItemIdentifier,
            "list_id": reminder.reminderListID ?? NSNull(),
            "title": reminder.reminderTitle ?? "",
            "completed": reminder.isCompleted,
        ]

        if let dueDate = reminder.dueDateComponents?.date {
            payload["due_date"] = isoString(from: dueDate)
        } else {
            payload["due_date"] = NSNull()
        }

        if let notes = reminder.reminderNotes, !notes.isEmpty {
            payload["notes"] = notes
        }

        return payload
    }

    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EventKitProviderError.serializationFailed
        }
        return string
    }
}

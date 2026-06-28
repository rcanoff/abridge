import EventKit
import Foundation

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

    static func reminderDictionary(from reminder: EKReminder) -> [String: Any] {
        var payload: [String: Any] = [
            "id": reminder.calendarItemIdentifier,
            "title": reminder.title ?? "",
            "completed": reminder.isCompleted,
        ]

        if let dueDate = reminder.dueDateComponents?.date {
            payload["due_date"] = isoString(from: dueDate)
        } else {
            payload["due_date"] = NSNull()
        }

        if let notes = reminder.notes, !notes.isEmpty {
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

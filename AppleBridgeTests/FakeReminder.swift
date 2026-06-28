@testable import AppleBridge
import Foundation

struct FakeReminder: ReminderRepresentable {
    let id: String
    let listID: String?
    let title: String?
    let completed: Bool
    let dueDateISO: String?
    let notes: String?

    var calendarItemIdentifier: String {
        id
    }

    var reminderListID: String? {
        listID
    }

    var reminderTitle: String? {
        title
    }

    var isCompleted: Bool {
        completed
    }

    var dueDateComponents: DateComponents? {
        guard let dueDateISO else { return nil }
        guard let date = ISO8601DateFormatter().date(from: dueDateISO) else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    var reminderNotes: String? {
        notes
    }
}

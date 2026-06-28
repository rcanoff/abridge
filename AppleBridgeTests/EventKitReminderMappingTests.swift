@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitReminderMapping")
struct EventKitReminderMappingTests {
    @Test
    func encodesJSONArray() throws {
        let json = try EventKitReminderMapping.jsonString(from: [["id": "1", "title": "A"]])
        #expect(json.contains("\"id\""))
        #expect(json.contains("\"title\""))
    }

    @Test
    func encodesReminderShapeFields() throws {
        let payload: [String: Any] = [
            "id": "rem-1",
            "title": "Buy milk",
            "completed": true,
            "due_date": "2026-06-28T12:00:00Z",
            "notes": "2%",
        ]

        let json = try EventKitReminderMapping.jsonString(from: [payload])

        #expect(json.contains("Buy milk"))
        #expect(json.contains("rem-1"))
        #expect(json.contains("due_date"))
    }
}

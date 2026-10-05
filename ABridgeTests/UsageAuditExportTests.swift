@testable import ABridge
import Foundation
import Testing

@Suite("UsageAuditExport")
struct UsageAuditExportTests {
    @Test
    func jsonStringUsesSnakeCaseKeys() {
        let entries = [
            UsageAuditEntry(
                timestampUtc: "2025-06-28T08:00:00.042Z",
                eventType: "tool_call",
                toolName: "eventkit.reminders.list_lists",
                success: true,
                durationMs: 42
            ),
        ]

        let json = UsageAuditExport.jsonString(from: entries)

        #expect(json.contains("\"timestamp_utc\""))
        #expect(json.contains("\"event_type\""))
        #expect(json.contains("\"tool_name\""))
        #expect(json.contains("\"duration_ms\""))
        #expect(!json.contains("timestampUtc"))
        #expect(!json.contains("eventType"))
        #expect(!json.contains("toolName"))
        #expect(!json.contains("durationMs"))
    }

    @Test
    func jsonStringOmitsSensitiveKeys() {
        let entries = [
            UsageAuditEntry(
                timestampUtc: "2025-06-28T08:00:00.042Z",
                eventType: "api_key_rotation",
                toolName: nil,
                success: true,
                durationMs: nil
            ),
        ]

        let json = UsageAuditExport.jsonString(from: entries).lowercased()

        #expect(!json.contains("bearer"))
        #expect(!json.contains("token"))
        #expect(!json.contains("payload"))
    }

    @Test
    func jsonStringEncodesMultipleEntriesInOrder() throws {
        let entries = [
            UsageAuditEntry(
                timestampUtc: "2025-06-28T08:00:00.000Z",
                eventType: "server_start",
                toolName: nil,
                success: true,
                durationMs: nil
            ),
            UsageAuditEntry(
                timestampUtc: "2025-06-28T08:00:01.000Z",
                eventType: "tool_call",
                toolName: "eventkit.reminders.list_lists",
                success: false,
                durationMs: 12
            ),
        ]

        let json = UsageAuditExport.jsonString(from: entries)

        let startIndex = try #require(json.range(of: "server_start")?.lowerBound)
        let toolIndex = try #require(json.range(of: "tool_call")?.lowerBound)
        #expect(startIndex < toolIndex)
    }
}

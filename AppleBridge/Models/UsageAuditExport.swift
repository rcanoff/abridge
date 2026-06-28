import Foundation

enum UsageAuditExport {
    struct Entry: Encodable {
        let timestampUtc: String
        let eventType: String
        let toolName: String?
        let success: Bool
        let durationMs: UInt64?

        enum CodingKeys: String, CodingKey {
            case timestampUtc = "timestamp_utc"
            case eventType = "event_type"
            case toolName = "tool_name"
            case success
            case durationMs = "duration_ms"
        }

        init(_ entry: UsageAuditEntry) {
            timestampUtc = entry.timestampUtc
            eventType = entry.eventType
            toolName = entry.toolName
            success = entry.success
            durationMs = entry.durationMs
        }
    }

    static func jsonString(from entries: [UsageAuditEntry]) -> String {
        let exportEntries = entries.map(Entry.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        guard let data = try? encoder.encode(exportEntries),
              let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }
}

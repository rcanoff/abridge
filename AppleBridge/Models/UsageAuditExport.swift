import Foundation

private enum UsageAuditExportCodingKeys: String, CodingKey {
    case timestampUtc = "timestamp_utc"
    case eventType = "event_type"
    case toolName = "tool_name"
    case success
    case durationMs = "duration_ms"
}

private struct UsageAuditExportEntry: Encodable {
    let timestampUtc: String
    let eventType: String
    let toolName: String?
    let success: Bool
    let durationMs: UInt64?

    init(_ entry: UsageAuditEntry) {
        timestampUtc = entry.timestampUtc
        eventType = entry.eventType
        toolName = entry.toolName
        success = entry.success
        durationMs = entry.durationMs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: UsageAuditExportCodingKeys.self)
        try container.encode(timestampUtc, forKey: .timestampUtc)
        try container.encode(eventType, forKey: .eventType)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
    }
}

enum UsageAuditExport {
    static func jsonString(from entries: [UsageAuditEntry]) -> String {
        let exportEntries = entries.map(UsageAuditExportEntry.init)
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

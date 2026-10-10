@testable import ABridge
import Foundation
import Testing

@Suite("SettingsStoreUsageAudit")
struct SettingsStoreUsageAuditTests {
    @Test
    @MainActor
    func refreshUsageAuditEntriesOrdersNewestFirst() async throws {
        let suiteName = "SettingsStoreTests.usageAuditRefresh"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockServerService()
        await mock.setUsageAuditEntriesResult([
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
                toolName: "eventkit_reminders_list_lists",
                success: true,
                durationMs: 42
            ),
        ])

        let appSettings = AppSettings(defaults: defaults)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.refreshUsageAuditEntries()

        #expect(settingsStore.usageAuditEntries.count == 2)
        #expect(settingsStore.usageAuditEntries.first?.eventType == "tool_call")
        #expect(settingsStore.usageAuditEntries.last?.eventType == "server_start")
    }

    @Test
    @MainActor
    func usageAuditExportJSONUsesChronologicalOrder() async throws {
        let suiteName = "SettingsStoreTests.usageAuditExport"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockServerService()
        await mock.setUsageAuditEntriesResult([
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
                toolName: "eventkit_reminders_list_lists",
                success: true,
                durationMs: 42
            ),
        ])

        let appSettings = AppSettings(defaults: defaults)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.refreshUsageAuditEntries()
        let json = settingsStore.usageAuditExportJSON()

        let startIndex = try #require(json.range(of: "server_start")?.lowerBound)
        let toolIndex = try #require(json.range(of: "tool_call")?.lowerBound)
        #expect(startIndex < toolIndex)
    }
}

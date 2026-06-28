@testable import AppleBridge
import Foundation
import Testing

@Suite("SettingsStoreUsageLogging")
struct SettingsStoreUsageLoggingTests {
    @Test
    @MainActor
    func applyUsageLoggingChangeHotUpdatesRunningServerWithoutRestart() async throws {
        let suiteName = "SettingsStoreTests.usageLoggingHotUpdate"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(
            port: 3020,
            enabledCapabilities: [],
            usageLoggingEnabled: true
        )
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applyUsageLoggingChange(false)

        #expect(appSettings.usageLoggingEnabled == false)
        #expect(await mock.setUsageLoggingEnabledCallCount == 1)
        #expect(await mock.usageLoggingEnabledState == false)
        #expect(await mock.startCallCount == 1)
    }

    @Test
    @MainActor
    func applyUsageLoggingChangePersistsWhenServerIsStopped() async throws {
        let suiteName = "SettingsStoreTests.usageLoggingStopped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applyUsageLoggingChange(false)

        #expect(appSettings.usageLoggingEnabled == false)
        #expect(await mock.setUsageLoggingEnabledCallCount == 1)
        #expect(defaults.bool(forKey: "usageLoggingEnabled") == false)
        #expect(await mock.startCallCount == 0)
    }

    @Test
    @MainActor
    func performLaunchRestoreAppliesPersistedUsageLoggingOnStart() async throws {
        let suiteName = "SettingsStoreTests.launchRestoreUsageLogging"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "mcpEnabled")
        defaults.set(false, forKey: "usageLoggingEnabled")

        let mock = MockServerService()
        let appSettings = AppSettings(defaults: defaults)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastStartUsageLoggingEnabled == false)
    }
}

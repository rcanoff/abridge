import Foundation
import Testing
@testable import AppleBridge

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test
    @MainActor
    func restoreServerOnLaunchStartsWhenMCPEnabled() async {
        let suiteName = "SettingsStoreTests.restore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.restoreServerOnLaunchIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func restoreServerOnLaunchSkipsWhenMCPEnabledOff() async {
        let suiteName = "SettingsStoreTests.skip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = false

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.restoreServerOnLaunchIfNeeded()

        #expect(await mock.startCallCount == 0)
    }
}
import Foundation
import Testing
@testable import AppleBridge

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test
    @MainActor
    func performLaunchRestoreAtAppStartupStartsWhenMCPEnabled() async {
        let suiteName = "SettingsStoreTests.launchRestore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func performLaunchRestoreAtAppStartupSkipsWhenMCPEnabledOff() async {
        let suiteName = "SettingsStoreTests.launchRestoreSkip"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = false

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 0)
    }

    @Test
    @MainActor
    func performLaunchRestoreIsIdempotent() async {
        let suiteName = "SettingsStoreTests.launchRestoreIdempotent"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()
        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
    }

    @Test
    @MainActor
    func performLaunchRestoreReadsPersistedSettingsWithoutViewLifecycle() async {
        let suiteName = "SettingsStoreTests.launchRestorePersisted"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Persist as if the user enabled MCP in a prior session.
        defaults.set(true, forKey: "mcpEnabled")
        defaults.set(3030, forKey: "mcpPort")
        defaults.set(["read"], forKey: "savedCapabilityIDs")

        let mock = MockServerService()

        // Mirror AppleBridgeApp.init() wiring — no SwiftUI views or onAppear callbacks.
        let appSettings = AppSettings(defaults: defaults)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(appSettings.mcpEnabled)
        #expect(appSettings.mcpPort == 3030)
        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastStartPort == 3030)
        #expect(await mock.lastEnabledCapabilities == ["eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func applyMCPEnabledChangeDoesNotDoubleStartAfterLaunchRestore() async {
        let suiteName = "SettingsStoreTests.launchRestoreNoDoubleStart"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.performLaunchRestoreIfNeeded()
        await settingsStore.applyMCPEnabledChange(true)

        #expect(await mock.startCallCount == 1)
    }
}
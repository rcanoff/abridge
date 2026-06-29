@testable import AppleBridge
import Foundation
import Testing

@Suite("SettingsStoreKeychainStorage")
struct SettingsStoreKeychainStorageTests {
    @Test
    @MainActor
    func applyKeychainStorageChangeRestartsRunningServer() async throws {
        let suiteName = "SettingsStoreKeychainStorageTests.restart"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.useKeychainForAPIKey = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applyKeychainStorageChange(false)

        #expect(appSettings.useKeychainForAPIKey == false)
        #expect(await mock.stopCallCount == 1)
        #expect(await mock.startCallCount == 2)
    }

    @Test
    @MainActor
    func applyKeychainStorageChangeLeavesServerRunningWhenMigrationFails() async throws {
        let suiteName = "SettingsStoreKeychainStorageTests.migrationFailure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.useKeychainForAPIKey = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            migrateTokenStorage: { _, _ in
                throw FileBearerTokenError(message: "migration failed")
            }
        )

        await settingsStore.applyKeychainStorageChange(false)

        #expect(appSettings.useKeychainForAPIKey == true)
        #expect(await mock.stopCallCount == 0)
        #expect(serverStore.runState == .running)
    }

    @Test
    @MainActor
    func applyKeychainStorageChangePersistsWithoutRestartWhenServerStopped() async throws {
        let suiteName = "SettingsStoreKeychainStorageTests.stopped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = false
        appSettings.useKeychainForAPIKey = true

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applyKeychainStorageChange(false)

        #expect(appSettings.useKeychainForAPIKey == false)
        #expect(await mock.stopCallCount == 0)
        #expect(await mock.startCallCount == 0)
    }
}

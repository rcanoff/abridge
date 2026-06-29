@testable import AppleBridge
import Foundation
import Testing

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test
    @MainActor
    func performLaunchRestoreAtAppStartupStartsWhenMCPEnabled() async throws {
        let suiteName = "SettingsStoreTests.launchRestore"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let permissionMock = MockRemindersPermissionService()
        permissionMock.status = .authorized
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionMock
        )

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func performLaunchRestoreAtAppStartupSkipsWhenMCPEnabledOff() async throws {
        let suiteName = "SettingsStoreTests.launchRestoreSkip"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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
    func performLaunchRestoreIsIdempotent() async throws {
        let suiteName = "SettingsStoreTests.launchRestoreIdempotent"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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
    func performLaunchRestoreReadsPersistedSettingsWithoutViewLifecycle() async throws {
        let suiteName = "SettingsStoreTests.launchRestorePersisted"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        // Persist as if the user enabled MCP in a prior session.
        defaults.set(true, forKey: "mcpEnabled")
        defaults.set(3030, forKey: "mcpPort")
        defaults.set(["read"], forKey: "savedCapabilityIDs")

        let permissionMock = MockRemindersPermissionService()
        permissionMock.status = .authorized
        let mock = MockServerService()

        // Mirror AppleBridgeApp.init() wiring — no SwiftUI views or onAppear callbacks.
        let appSettings = AppSettings(defaults: defaults)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionMock
        )

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(appSettings.mcpEnabled)
        #expect(appSettings.mcpPort == 3030)
        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastStartPort == 3030)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func launchRestoreFailureSurvivesPostRestoreRefresh() async throws {
        let suiteName = "SettingsStoreTests.launchRestoreFailure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        await mock.setStartError(ServerOperationError(message: "failed to bind server: port in use"))
        await mock.setRefreshResult(.stopped)
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        // Mirror AppleBridgeApp.init() launch task ordering.
        await settingsStore.performLaunchRestoreIfNeeded()
        await serverStore.refreshBearerToken()
        await serverStore.refreshStatus()

        #expect(serverStore.runState == .error("failed to bind server: port in use"))
        #expect(serverStore.lastError == "failed to bind server: port in use")
    }

    @Test
    @MainActor
    func resetBearerTokenShowsNoticeOnlyAfterSuccessfulReset() async throws {
        let suiteName = "SettingsStoreTests.resetBearerTokenSuccess"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = false

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.resetBearerToken()

        #expect(settingsStore.tokenResetNotice == "Bearer token reset. Update your MCP client with the new token.")
        #expect(serverStore.lastError == nil)
    }

    @Test
    @MainActor
    func resetBearerTokenShowsRestartNoticeWhenServerWasRunning() async throws {
        let suiteName = "SettingsStoreTests.resetBearerTokenRestartNotice"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.resetBearerToken()

        #expect(settingsStore.tokenResetNotice == "Server restarted with a new token. Update your MCP client.")
        #expect(serverStore.lastError == nil)
    }

    @Test
    @MainActor
    func resetBearerTokenClearsNoticeWhenResetFails() async throws {
        let suiteName = "SettingsStoreTests.resetBearerTokenFailure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = false

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.resetBearerToken()
        #expect(settingsStore.tokenResetNotice != nil)

        await mock.setResetBearerTokenError(ServerOperationError(message: "failed to save bearer token"))
        await settingsStore.resetBearerToken()

        #expect(settingsStore.tokenResetNotice == nil)
        #expect(serverStore.lastError == "failed to save bearer token")
    }

    @Test
    @MainActor
    func resetBearerTokenOmitsNoticeWhenRestartFailsAfterRotation() async throws {
        let suiteName = "SettingsStoreTests.resetBearerTokenRestartFailure"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        #expect(serverStore.runState == .running)

        await mock.setStartError(ServerOperationError(message: "failed to bind server: port in use"))
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.resetBearerToken()

        #expect(settingsStore.tokenResetNotice == nil)
        #expect(serverStore.lastError == "failed to bind server: port in use")
    }

    @Test
    @MainActor
    func applySavedCapabilitiesOmitsShippedCapabilitiesWithoutRemindersAccess() async throws {
        let suiteName = "SettingsStoreTests.gatedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false
        )

        #expect(await mock.startCallCount == 2)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])
    }

    @Test
    @MainActor
    func applySavedCapabilitiesOmitsContactsCapabilitiesWithoutAuthorization() async throws {
        let suiteName = "SettingsStoreTests.contactsGatedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["contacts-read"])

        let contactsMock = MockContactsPermissionService()
        contactsMock.status = .denied
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            contactsPermissionService: contactsMock
        )

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false
        )

        #expect(await mock.startCallCount == 2)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])
    }

    @Test
    @MainActor
    func resetBearerTokenOmitsShippedCapabilitiesWithoutRemindersAccess() async throws {
        let suiteName = "SettingsStoreTests.gatedReset"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let permissionMock = MockRemindersPermissionService()
        permissionMock.status = .notDetermined
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionMock
        )

        await settingsStore.resetBearerToken()

        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])
    }

    @Test
    @MainActor
    func performLaunchRestoreOmitsShippedCapabilitiesWithoutRemindersAccess() async throws {
        let suiteName = "SettingsStoreTests.gatedLaunchRestore"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let permissionMock = MockRemindersPermissionService()
        permissionMock.status = .denied
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionMock
        )

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])
    }

    @Test
    @MainActor
    func applySavedCapabilitiesAppliesShippedCapabilitiesWhenRemindersAuthorized() async throws {
        let suiteName = "SettingsStoreTests.authorizedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["read"])

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: true,
            eventsAuthorized: false,
            contactsAuthorized: false
        )

        #expect(await mock.startCallCount == 2)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func applyMCPEnabledChangeDoesNotDoubleStartAfterLaunchRestore() async throws {
        let suiteName = "SettingsStoreTests.launchRestoreNoDoubleStart"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
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

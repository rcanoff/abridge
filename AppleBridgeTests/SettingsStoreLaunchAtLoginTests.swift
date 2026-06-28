@testable import AppleBridge
import Foundation
import Testing

@Suite("SettingsStore Launch at Login")
struct SettingsStoreLaunchAtLoginTests {
    @Test
    @MainActor
    func applyLaunchAtLoginChangeEnableRegistersAndPersists() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.enable"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)

        let launchAtLoginMock = MockLaunchAtLoginService()
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.applyLaunchAtLoginChange(true)

        #expect(launchAtLoginMock.registerCallCount == 1)
        #expect(appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError == nil)
    }

    @Test
    @MainActor
    func applyLaunchAtLoginChangeDisableUnregistersAndPersists() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.disable"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = true
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.applyLaunchAtLoginChange(false)

        #expect(launchAtLoginMock.unregisterCallCount == 1)
        #expect(!appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError == nil)
    }

    @Test
    @MainActor
    func applyLaunchAtLoginChangeEnableFailureLeavesSettingFalseAndSetsError() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.enableFail"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.registerError = LaunchAtLoginError.registrationFailed
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: ServerStore(serverService: MockServerService()),
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.applyLaunchAtLoginChange(true)

        #expect(launchAtLoginMock.registerCallCount == 1)
        #expect(!appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError != nil)
    }

    @Test
    @MainActor
    func applyLaunchAtLoginChangeDisableFailureLeavesSettingTrueAndSetsError() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.disableFail"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = true
        launchAtLoginMock.unregisterError = LaunchAtLoginError.unregistrationFailed
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: ServerStore(serverService: MockServerService()),
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.applyLaunchAtLoginChange(false)

        #expect(launchAtLoginMock.unregisterCallCount == 1)
        #expect(appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError != nil)
    }

    @Test
    @MainActor
    func performLaunchAtLoginReconcileSyncsSettingToSystemWhenSystemOff() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.reconcileOff"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = false
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: ServerStore(serverService: MockServerService()),
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.performLaunchAtLoginReconcileIfNeeded()

        #expect(!appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError == nil)
    }

    @Test
    @MainActor
    func performLaunchAtLoginReconcileSyncsSettingToSystemWhenSystemOn() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.reconcileOn"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = true
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: ServerStore(serverService: MockServerService()),
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.performLaunchAtLoginReconcileIfNeeded()

        #expect(appSettings.launchAtLogin)
        #expect(settingsStore.launchAtLoginError == nil)
    }

    @Test
    @MainActor
    func performLaunchAtLoginReconcileIsIdempotent() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.reconcileIdempotent"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = false
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: ServerStore(serverService: MockServerService()),
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.performLaunchAtLoginReconcileIfNeeded()
        launchAtLoginMock.isRegistered = true
        await settingsStore.performLaunchAtLoginReconcileIfNeeded()

        #expect(!appSettings.launchAtLogin)
    }

    @Test
    @MainActor
    func launchReconcileRunsBeforeMCPRestore() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.launchOrdering"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true
        appSettings.mcpEnabled = true

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = false
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.performLaunchAtLoginReconcileIfNeeded()
        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(!appSettings.launchAtLogin)
        #expect(await mock.startCallCount == 1)
    }

    @Test
    @MainActor
    func launchAtLoginOnDoesNotForceMCPStartWhenDisabled() async throws {
        let suiteName = "SettingsStoreLaunchAtLoginTests.mcpIndependent"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true
        appSettings.mcpEnabled = false

        let launchAtLoginMock = MockLaunchAtLoginService()
        launchAtLoginMock.isRegistered = true
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            launchAtLoginService: launchAtLoginMock
        )

        await settingsStore.performLaunchAtLoginReconcileIfNeeded()
        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(appSettings.launchAtLogin)
        #expect(await mock.startCallCount == 0)
    }
}

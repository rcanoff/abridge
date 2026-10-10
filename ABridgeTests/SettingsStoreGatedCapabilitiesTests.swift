@testable import ABridge
import Foundation
import Testing

@Suite("SettingsStoreGatedCapabilities")
struct SettingsStoreGatedCapabilitiesTests {
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
            contactsAuthorized: false,
            locationAuthorized: false
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
            contactsAuthorized: false,
            locationAuthorized: false
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
            contactsAuthorized: false,
            locationAuthorized: false
        )

        #expect(await mock.startCallCount == 2)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "eventkit.reminders.read"])
    }

    @Test
    @MainActor
    func applySavedCapabilitiesIncludesMapKitWithoutLocationAccess() async throws {
        let suiteName = "SettingsStoreTests.mapkitWithoutLocation"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["mapkit-search"])

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )

        #expect(await mock.startCallCount == 2)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "mapkit.search"])
    }

    @Test
    @MainActor
    func applySavedCapabilitiesGatesCoreLocationOnLocationAccess() async throws {
        let suiteName = "SettingsStoreTests.corelocationLocationAuthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["corelocation-read"])

        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let locationService = MockLocationPermissionService()
        locationService.status = .authorized

        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            locationPermissionService: locationService
        )

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: true
        )
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "corelocation.read"])
    }
}

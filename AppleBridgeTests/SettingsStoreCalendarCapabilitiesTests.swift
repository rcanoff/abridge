@testable import AppleBridge
import Foundation
import Testing

@Suite("SettingsStoreCalendarCapabilities")
struct SettingsStoreCalendarCapabilitiesTests {
    @Test
    @MainActor
    func performLaunchRestoreAppliesCalendarCapabilitiesWhenEventsAuthorized() async throws {
        let suiteName = "SettingsStoreCalendarCapabilitiesTests.launchRestore"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["calendars-read"])

        let remindersMock = MockRemindersPermissionService()
        remindersMock.status = .denied
        let eventsMock = MockEventsPermissionService()
        eventsMock.status = .authorized
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: remindersMock,
            eventsPermissionService: eventsMock
        )

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read", "eventkit.calendars.read"])
    }

    @Test
    @MainActor
    func performLaunchRestoreOmitsCalendarCapabilitiesWithoutEventsAccess() async throws {
        let suiteName = "SettingsStoreCalendarCapabilitiesTests.launchRestoreDenied"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["calendars-read"])

        let eventsMock = MockEventsPermissionService()
        eventsMock.status = .denied
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            eventsPermissionService: eventsMock
        )

        await settingsStore.performLaunchRestoreIfNeeded()

        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastEnabledCapabilities == ["diagnostics.read"])
    }
}

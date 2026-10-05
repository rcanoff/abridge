@testable import ABridge
import Foundation

final class MockABridgeAppStoreMaker: ABridgeAppStoreMaking, @unchecked Sendable {
    private let suiteName: String
    private(set) var makeStoresCallCount = 0

    init(suiteName: String = "MockABridgeAppStoreMaker.stores") {
        self.suiteName = suiteName
    }

    @MainActor
    func makeStores() -> ABridgeAppBootstrap.Stores {
        makeStoresCallCount += 1
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let permissionService = RemindersPermissionService()
        let eventsPermissionService = EventsPermissionService()
        let contactsPermissionService = ContactsPermissionService()
        let locationPermissionService = LocationPermissionService()
        let store = AppStore(
            permissionService: permissionService,
            eventsPermissionService: eventsPermissionService,
            contactsPermissionService: contactsPermissionService,
            locationPermissionService: locationPermissionService
        )
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionService,
            eventsPermissionService: eventsPermissionService,
            contactsPermissionService: contactsPermissionService,
            locationPermissionService: locationPermissionService
        )
        let permissionsStore = PermissionsStore(appSettings: appSettings)
        return ABridgeAppBootstrap.Stores(
            appSettings: appSettings,
            serverStore: serverStore,
            store: store,
            permissionsStore: permissionsStore,
            settingsStore: settingsStore,
            calendarSharingStore: CalendarSharingStore(defaults: defaults) { _ in [] }
        )
    }
}

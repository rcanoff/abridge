@testable import AppleBridge
import Foundation

final class MockAppleBridgeAppStoreMaker: AppleBridgeAppStoreMaking, @unchecked Sendable {
    private let suiteName: String
    private(set) var makeStoresCallCount = 0

    init(suiteName: String = "MockAppleBridgeAppStoreMaker.stores") {
        self.suiteName = suiteName
    }

    @MainActor
    func makeStores() -> AppleBridgeAppBootstrap.Stores {
        makeStoresCallCount += 1
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let permissionService = RemindersPermissionService()
        let eventsPermissionService = EventsPermissionService()
        let contactsPermissionService = ContactsPermissionService()
        let store = AppStore(
            permissionService: permissionService,
            eventsPermissionService: eventsPermissionService,
            contactsPermissionService: contactsPermissionService
        )
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionService,
            eventsPermissionService: eventsPermissionService,
            contactsPermissionService: contactsPermissionService
        )
        let permissionsStore = PermissionsStore(appSettings: appSettings)
        return AppleBridgeAppBootstrap.Stores(
            appSettings: appSettings,
            serverStore: serverStore,
            store: store,
            permissionsStore: permissionsStore,
            settingsStore: settingsStore
        )
    }
}
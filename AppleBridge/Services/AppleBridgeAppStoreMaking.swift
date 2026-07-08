import Foundation

protocol AppleBridgeAppStoreMaking: Sendable {
    @MainActor func makeStores() -> AppleBridgeAppBootstrap.Stores
}

struct ProductionAppleBridgeAppStoreMaker: AppleBridgeAppStoreMaking {
    @MainActor
    func makeStores() -> AppleBridgeAppBootstrap.Stores {
        let appSettings = AppSettings()
        let serverStore = ServerStore(
            serverService: ServerService(
                tokenStore: BearerTokenStoreFactory.make(useKeychain: appSettings.useKeychainForAPIKey)
            )
        )
        let permissionService = RemindersPermissionService()
        let eventsPermissionService = EventsPermissionService()
        let contactsPermissionService = ContactsPermissionService()
        // Shared with MapKit MCP gates so UI and tools see the same sticky location status.
        let locationPermissionService = LiveLocationPermission.service
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
        return AppleBridgeAppBootstrap.Stores(
            appSettings: appSettings,
            serverStore: serverStore,
            store: store,
            permissionsStore: permissionsStore,
            settingsStore: settingsStore
        )
    }
}

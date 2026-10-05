import Foundation

protocol ABridgeAppStoreMaking: Sendable {
    @MainActor func makeStores() -> ABridgeAppBootstrap.Stores
}

struct ProductionABridgeAppStoreMaker: ABridgeAppStoreMaking {
    @MainActor
    func makeStores() -> ABridgeAppBootstrap.Stores {
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
        return ABridgeAppBootstrap.Stores(
            appSettings: appSettings,
            serverStore: serverStore,
            store: store,
            permissionsStore: permissionsStore,
            settingsStore: settingsStore,
            // Shared with EventKit MCP tools so the picker and provider see one selection.
            calendarSharingStore: LiveEventKitEnvironment.calendarSharingStore
        )
    }
}

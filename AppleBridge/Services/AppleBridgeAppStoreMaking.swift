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
        let contactsPermissionService = ContactsPermissionService()
        let store = AppStore(
            permissionService: permissionService,
            contactsPermissionService: contactsPermissionService
        )
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionService,
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

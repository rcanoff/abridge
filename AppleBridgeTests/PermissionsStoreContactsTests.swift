@testable import AppleBridge
import Foundation
import Testing

@Suite("PermissionsStoreContacts")
struct PermissionsStoreContactsTests {
    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsReadEnabled() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-read")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsSearchEnabled() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsSearchShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-search")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsCreateEnabled() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsCreateShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-create")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsEditEnabled() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsEditShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-edit")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsDeleteEnabled() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsDeleteShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-delete")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessOnlyForShippedCapabilities() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsUnshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "not-in-catalog")

        #expect(store.requiresAppleContactsAccess == false)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsDeleteWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsDeleteShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-delete",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsCreateWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsCreateShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-create",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsEditWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsEditShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-edit",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsSearchWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsSearchShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-search",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreContactsTests.contactsShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-read",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            ) == false
        )
    }
}

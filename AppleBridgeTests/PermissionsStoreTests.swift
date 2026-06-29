@testable import AppleBridge
import Foundation
import Testing

@Suite("PermissionsStore")
struct PermissionsStoreIntegrationTests {
    @Test
    @MainActor
    func setCheckedPersistsImmediately() throws {
        let suiteName = "PermissionsStoreTests.immediatePersist"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        let store = PermissionsStore(appSettings: appSettings)

        store.setChecked(true, for: "read")
        store.setChecked(true, for: "create")

        #expect(store.checkedCapabilityIDs == ["read", "create"])
        #expect(store.savedCapabilityIDs == ["read", "create"])
    }

    @Test
    @MainActor
    func enablingMCPCapabilityDoesNotTrackSeparateAppleFlag() throws {
        let suiteName = "PermissionsStoreTests.noAppleFlag"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "read")

        #expect(store.requiresAppleRemindersAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleRemindersAccessOnlyForShippedCapabilities() throws {
        let suiteName = "PermissionsStoreTests.shippedOnly"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "not-in-catalog")

        #expect(store.requiresAppleRemindersAccess == false)
    }

    @Test
    @MainActor
    func requiresAppleRemindersAccessWhenDeleteCapabilityEnabled() throws {
        let suiteName = "PermissionsStoreTests.deleteShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "delete")

        #expect(store.requiresAppleRemindersAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleRemindersAccessWhenCreateCapabilityEnabled() throws {
        let suiteName = "PermissionsStoreTests.createShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "create")

        #expect(store.requiresAppleRemindersAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleRemindersAccessWhenEditCapabilityEnabled() throws {
        let suiteName = "PermissionsStoreTests.editShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "edit")

        #expect(store.requiresAppleRemindersAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleRemindersAccessWhenNoMCPCapabilitiesEnabled() throws {
        let suiteName = "PermissionsStoreTests.notRequired"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(store.requiresAppleRemindersAccess == false)
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingWhenRemindersAuthorized() throws {
        let suiteName = "PermissionsStoreTests.applyWhenAuthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "read",
                remindersAuthorized: true,
                eventsAuthorized: false,
                contactsAuthorized: false
            )
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedCapabilityWithoutRemindersAccess() throws {
        let suiteName = "PermissionsStoreTests.skipApplyWhenUnauthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "read",
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterDisablingWithoutRemindersAccess() throws {
        let suiteName = "PermissionsStoreTests.applyWhenDisabling"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: false,
                capabilityID: "read",
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false
            )
        )
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingCalendarWhenEventsAuthorized() throws {
        let suiteName = "PermissionsStoreTests.calendarApplyWhenAuthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "calendars-read",
                remindersAuthorized: false,
                eventsAuthorized: true,
                contactsAuthorized: false
            )
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingCalendarWithoutEventsAccess() throws {
        let suiteName = "PermissionsStoreTests.calendarSkipApplyWhenUnauthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "calendars-read",
                remindersAuthorized: true,
                eventsAuthorized: false,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsReadEnabled() throws {
        let suiteName = "PermissionsStoreTests.contactsShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-read")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsSearchEnabled() throws {
        let suiteName = "PermissionsStoreTests.contactsSearchShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-search")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsCreateEnabled() throws {
        let suiteName = "PermissionsStoreTests.contactsCreateShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-create")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessWhenShippedContactsEditEnabled() throws {
        let suiteName = "PermissionsStoreTests.contactsEditShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-edit")

        #expect(store.requiresAppleContactsAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleContactsAccessOnlyForShippedCapabilities() throws {
        let suiteName = "PermissionsStoreTests.contactsUnshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "contacts-delete")

        #expect(store.requiresAppleContactsAccess == false)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsCreateWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreTests.contactsCreateShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-create",
                remindersAuthorized: true,
                eventsAuthorized: true,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsEditWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreTests.contactsEditShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-edit",
                remindersAuthorized: true,
                eventsAuthorized: true,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsSearchWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreTests.contactsSearchShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-search",
                remindersAuthorized: true,
                eventsAuthorized: true,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingShippedContactsWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreTests.contactsShippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "contacts-read",
                remindersAuthorized: true,
                eventsAuthorized: true,
                contactsAuthorized: false
            ) == false
        )
    }

    @Test
    @MainActor
    func uncheckingLastCapabilityClearsRequirement() throws {
        let suiteName = "PermissionsStoreTests.clearRequirement"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "read")
        store.setChecked(false, for: "read")

        #expect(store.requiresAppleRemindersAccess == false)
    }
}

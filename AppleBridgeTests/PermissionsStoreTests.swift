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
    func requiresAppleRemindersAccessWhenNoMCPCapabilitiesEnabled() throws {
        let suiteName = "PermissionsStoreTests.notRequired"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(store.requiresAppleRemindersAccess == false)
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

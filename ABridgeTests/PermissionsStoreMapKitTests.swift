@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreMapKit")
struct PermissionsStoreMapKitTests {
    @Test
    @MainActor
    func requiresAppleLocationAccessIsFalseForShippedMapKitToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.shipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-search")

        #expect(store.requiresAppleLocationAccess == false)
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingMapKitWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreMapKitTests.shippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "mapkit-search",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: false,
                    eventsAuthorized: false,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            )
        )
    }
}

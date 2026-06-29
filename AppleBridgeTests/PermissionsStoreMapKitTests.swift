@testable import AppleBridge
import Foundation
import Testing

@Suite("PermissionsStoreMapKit")
struct PermissionsStoreMapKitTests {
    @Test
    @MainActor
    func requiresAppleLocationAccessIsFalseForUnshippedMapKitToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.unshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-search")

        #expect(store.requiresAppleLocationAccess == false)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingUnshippedMapKitWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreMapKitTests.unshippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "mapkit-search",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: true,
                    locationAuthorized: false
                )
            )
        )
    }
}

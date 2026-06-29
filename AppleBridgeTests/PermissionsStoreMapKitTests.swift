@testable import AppleBridge
import Foundation
import Testing

@Suite("PermissionsStoreMapKit")
struct PermissionsStoreMapKitTests {
    @Test
    @MainActor
    func requiresAppleLocationAccessIsTrueForShippedMapKitToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.shipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-search")

        #expect(store.requiresAppleLocationAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleLocationAccessIsTrueForShippedMapKitRoutingToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.routingShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-routing")

        #expect(store.requiresAppleLocationAccess == true)
    }

    @Test
    @MainActor
    func requiresAppleLocationAccessIsTrueForShippedMapKitGeocodeToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.geocodeShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-geocode")

        #expect(store.requiresAppleLocationAccess == true)
    }

    @Test @MainActor func requiresAppleLocationAccessIsTrueForShippedMapKitLocationToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.locationShipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName)); defaults.removePersistentDomain(forName: suiteName)
        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults)); store.setChecked(true, for: "mapkit-location")
        #expect(store.requiresAppleLocationAccess == true)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingMapKitWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreMapKitTests.shippedApply"
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
            ) == false
        )
    }
}

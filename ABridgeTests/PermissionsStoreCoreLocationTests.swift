@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreCoreLocation")
struct PermissionsStoreCoreLocationTests {
    @Test
    @MainActor
    func requiresAppleLocationAccessIsTrueForShippedCoreLocationToggle() throws {
        let suiteName = "PermissionsStoreCoreLocationTests.shipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "corelocation-read")

        #expect(store.requiresAppleLocationAccess == true)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingCoreLocationWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreCoreLocationTests.shippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "corelocation-read",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: true,
                    locationAuthorized: false
                )
            ) == false
        )
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingCoreLocationWhenAuthorized() throws {
        let suiteName = "PermissionsStoreCoreLocationTests.authorizedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "corelocation-read",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: false,
                    eventsAuthorized: false,
                    contactsAuthorized: false,
                    locationAuthorized: true
                )
            )
        )
    }
}

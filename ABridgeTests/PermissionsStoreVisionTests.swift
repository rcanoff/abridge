@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreVision")
struct PermissionsStoreVisionTests {
    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingUnshippedVisionToggle() throws {
        let suiteName = "PermissionsStoreVisionTests.unshippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "vision-text",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: false,
                    eventsAuthorized: false,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            )
        )
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingVisionDocumentToggle() throws {
        let suiteName = "PermissionsStoreVisionTests.documentApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "vision-document",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: true,
                    locationAuthorized: true
                )
            )
        )
    }
}

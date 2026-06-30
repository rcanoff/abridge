@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettingsVision")
struct AppSettingsVisionTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesVisionTextWhenShippedAndEnabled() throws {
        let suiteName = "AppSettingsVisionTests.shipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["vision-text", "vision-barcodes"])

        #expect(appSettings.enabledVisionCapabilityIDs == ["vision.text", "vision.barcodes"])
        let capabilities = appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )
        #expect(capabilities.contains("vision.text"))
        #expect(capabilities.contains("vision.barcodes"))
        #expect(capabilities.contains("diagnostics.read"))
    }

    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesVisionDocumentWhenShippedAndEnabled() throws {
        let suiteName = "AppSettingsVisionTests.document"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["vision-document"])

        #expect(appSettings.enabledVisionCapabilityIDs == ["vision.document"])
        let capabilities = appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )
        #expect(capabilities.contains("vision.document"))
    }

    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesVisionFacesWhenShippedAndEnabled() throws {
        let suiteName = "AppSettingsVisionTests.faces"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["vision-faces"])

        #expect(appSettings.enabledVisionCapabilityIDs == ["vision.faces"])
        let capabilities = appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )
        #expect(capabilities.contains("vision.faces"))
    }
}

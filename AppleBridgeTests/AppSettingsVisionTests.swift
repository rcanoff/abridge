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

        #expect(appSettings.enabledVisionCapabilityIDs == ["vision.text"])
        let capabilities = appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false
        )
        #expect(capabilities.contains("vision.text"))
        #expect(!capabilities.contains("vision.barcodes"))
        #expect(capabilities.contains("diagnostics.read"))
    }
}

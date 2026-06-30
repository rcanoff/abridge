@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettingsVision")
struct AppSettingsVisionTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsUnshippedVisionCapabilities() throws {
        let suiteName = "AppSettingsVisionTests.unshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["vision-text", "vision-barcodes"])

        #expect(appSettings.enabledVisionCapabilityIDs.isEmpty)
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: false
            ) == ["diagnostics.read"]
        )
    }
}

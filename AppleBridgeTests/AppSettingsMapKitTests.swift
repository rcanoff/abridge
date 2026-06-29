@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettingsMapKit")
struct AppSettingsMapKitTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsMapKitCapabilitiesWithoutAuthorization() throws {
        let suiteName = "AppSettingsMapKitTests.mapkitServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["mapkit-search"])

        #expect(appSettings.enabledMapKitCapabilityIDs.isEmpty)
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: false
            ) == ["diagnostics.read"]
        )
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: true
            ) == ["diagnostics.read"]
        )
    }
}

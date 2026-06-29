@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettingsContacts")
struct AppSettingsContactsTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsContactsCapabilitiesWithoutAuthorization() throws {
        let suiteName = "AppSettingsContactsTests.contactsServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["contacts-read"])

        #expect(appSettings.enabledContactsCapabilityIDs.isEmpty)
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false
            ) == ["diagnostics.read"]
        )
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: true
            ) == ["diagnostics.read"]
        )
    }
}

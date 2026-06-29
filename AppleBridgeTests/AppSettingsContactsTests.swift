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

        #expect(appSettings.enabledContactsCapabilityIDs == ["contacts.read"])
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
            ) == ["diagnostics.read", "contacts.read"]
        )
    }

    @Test
    @MainActor
    func enabledContactsCapabilityIDsIncludesCheckedContactsDeleteCapability() throws {
        let suiteName = "AppSettingsContactsTests.contactsDeleteCapability"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["contacts-delete"])

        #expect(appSettings.enabledContactsCapabilityIDs == ["contacts.delete"])
    }

    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesContactsSearchWhenAuthorized() throws {
        let suiteName = "AppSettingsContactsTests.contactsSearchServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["contacts-search"])

        #expect(appSettings.enabledContactsCapabilityIDs == ["contacts.search"])
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
            ) == ["diagnostics.read", "contacts.search"]
        )
    }
}

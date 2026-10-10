@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsCoreLocation")
struct AppSettingsCoreLocationTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesCoreLocationOnlyWhenLocationAuthorized() throws {
        let suiteName = "AppSettingsCoreLocationTests.locationServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["corelocation-read"])

        #expect(appSettings.enabledCoreLocationCapabilityIDs == ["corelocation.read"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false) == ["diagnostics.read"]
        )
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true)
                == ["diagnostics.read", "corelocation.read"]
        )
    }

    @MainActor
    private func serverEnabledCapabilities(
        for appSettings: AppSettings,
        locationAuthorized: Bool
    ) -> [String] {
        appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: locationAuthorized
        )
    }
}

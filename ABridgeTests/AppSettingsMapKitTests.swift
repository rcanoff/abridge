@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsMapKit")
struct AppSettingsMapKitTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesMapKitWithoutLocationAccess() throws {
        let suiteName = "AppSettingsMapKitTests.mapkitServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["mapkit-search"])

        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.search"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false)
                == ["diagnostics.read", "mapkit.search"]
        )
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true)
                == ["diagnostics.read", "mapkit.search"]
        )

        appSettings.saveCapabilityIDs(["mapkit-geocode"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.geocode"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false).contains("mapkit.geocode")
        )

        appSettings.saveCapabilityIDs(["mapkit-routing"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.routing"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false).contains("mapkit.routing")
        )

        appSettings.saveCapabilityIDs(["mapkit-navigation"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.navigation"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false).contains("mapkit.navigation")
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

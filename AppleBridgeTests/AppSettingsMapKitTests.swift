@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettingsMapKit")
struct AppSettingsMapKitTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsIncludesMapKitSearchWhenLocationAuthorized() throws {
        let suiteName = "AppSettingsMapKitTests.mapkitServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["mapkit-search"])

        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.search"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: false) == ["diagnostics.read"]
        )
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true)
                == ["diagnostics.read", "mapkit.search"]
        )

        appSettings.saveCapabilityIDs(["mapkit-geocode"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.geocode"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true).contains("mapkit.geocode")
        )

        appSettings.saveCapabilityIDs(["mapkit-routing"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.routing"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true).contains("mapkit.routing")
        )

        appSettings.saveCapabilityIDs(["mapkit-navigation"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.navigation"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true).contains("mapkit.navigation")
        )

        appSettings.saveCapabilityIDs(["mapkit-location"])
        #expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.location"])
        #expect(
            serverEnabledCapabilities(for: appSettings, locationAuthorized: true).contains("mapkit.location")
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
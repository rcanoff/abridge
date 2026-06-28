@testable import AppleBridge
import Foundation
import Testing

@Suite("AppSettings")
struct AppSettingsTests {
    @Test
    @MainActor
    func initLoadsValidPersistedPort() throws {
        let suiteName = "AppSettingsTests.validPort"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(3030, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3030)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortIsZero() throws {
        let suiteName = "AppSettingsTests.zeroPort"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(0, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortExceedsUInt16Max() throws {
        let suiteName = "AppSettingsTests.overflowPort"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(70000, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortIsNegative() throws {
        let suiteName = "AppSettingsTests.negativePort"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(-1, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsShippedCapabilitiesWithoutRemindersAccess() throws {
        let suiteName = "AppSettingsTests.gatedCapabilities"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["read"])

        #expect(appSettings.enabledMCPCapabilityIDs == ["eventkit.reminders.read"])
        #expect(appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: false) == [])
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: true) == ["eventkit.reminders.read"]
        )
    }

    @Test
    @MainActor
    func initLoadsMaximumValidPort() throws {
        let suiteName = "AppSettingsTests.maxPort"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(65535, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 65535)
    }
}

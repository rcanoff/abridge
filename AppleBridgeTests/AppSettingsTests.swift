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
    func enabledMCPCapabilityIDsIncludesCheckedCalendarCreateCapability() throws {
        let suiteName = "AppSettingsTests.calendarCreateCapability"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["calendars-create"])

        #expect(appSettings.enabledCalendarCapabilityIDs == ["eventkit.calendars.create"])
    }

    @Test
    @MainActor
    func enabledMCPCapabilityIDsIncludesCheckedCalendarCapabilities() throws {
        let suiteName = "AppSettingsTests.calendarCapabilities"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["calendars-read"])

        #expect(appSettings.enabledCalendarCapabilityIDs == ["eventkit.calendars.read"])
        #expect(appSettings.enabledMCPCapabilityIDs == ["eventkit.calendars.read"])
    }

    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsGatesCalendarCapabilitiesOnEventsAuthorization() throws {
        let suiteName = "AppSettingsTests.calendarServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["calendars-read"])

        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: false, eventsAuthorized: true)
                == ["diagnostics.read", "eventkit.calendars.read"]
        )
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: false, eventsAuthorized: false)
                == ["diagnostics.read"]
        )
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
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: false, eventsAuthorized: false)
                == ["diagnostics.read"]
        )
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: true, eventsAuthorized: false)
                == ["diagnostics.read", "eventkit.reminders.read"]
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

    @Test
    @MainActor
    func usageLoggingEnabledDefaultsToTrueOnFreshInstall() throws {
        let suiteName = "AppSettingsTests.usageLoggingDefault"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.usageLoggingEnabled == true)
    }

    @Test
    @MainActor
    func usageLoggingEnabledPersistsAcrossInstances() throws {
        let suiteName = "AppSettingsTests.usageLoggingPersist"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.usageLoggingEnabled = false

        let reloaded = AppSettings(defaults: defaults)

        #expect(reloaded.usageLoggingEnabled == false)
        #expect(defaults.bool(forKey: "usageLoggingEnabled") == false)
    }

    @Test
    @MainActor
    func usageLoggingEnabledLoadsPersistedTrueValue() throws {
        let suiteName = "AppSettingsTests.usageLoggingPersistTrue"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "usageLoggingEnabled")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.usageLoggingEnabled == true)
    }

    @Test
    @MainActor
    func launchAtLoginDefaultsToFalseOnFreshInstall() throws {
        let suiteName = "AppSettingsTests.launchAtLoginDefault"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.launchAtLogin == false)
    }

    @Test
    @MainActor
    func launchAtLoginPersistsAcrossInstances() throws {
        let suiteName = "AppSettingsTests.launchAtLoginPersist"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.launchAtLogin = true

        let reloaded = AppSettings(defaults: defaults)

        #expect(reloaded.launchAtLogin == true)
        #expect(defaults.bool(forKey: "launchAtLogin"))
    }
}

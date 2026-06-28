import Foundation
import Testing
@testable import AppleBridge

@Suite("AppSettings")
struct AppSettingsTests {
    @Test
    @MainActor
    func initLoadsValidPersistedPort() {
        let suiteName = "AppSettingsTests.validPort"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(3030, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3030)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortIsZero() {
        let suiteName = "AppSettingsTests.zeroPort"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(0, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortExceedsUInt16Max() {
        let suiteName = "AppSettingsTests.overflowPort"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(70_000, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func initFallsBackToDefaultWhenPortIsNegative() {
        let suiteName = "AppSettingsTests.negativePort"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(-1, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 3020)
    }

    @Test
    @MainActor
    func initLoadsMaximumValidPort() {
        let suiteName = "AppSettingsTests.maxPort"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(65_535, forKey: "mcpPort")

        let appSettings = AppSettings(defaults: defaults)

        #expect(appSettings.mcpPort == 65_535)
    }
}
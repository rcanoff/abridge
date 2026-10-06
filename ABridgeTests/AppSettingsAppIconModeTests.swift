@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsAppIconMode")
struct AppSettingsAppIconModeTests {
    @Test
    @MainActor
    func appIconModeDefaultsToMenuBar() throws {
        let suiteName = "AppSettingsAppIconModeTests.default"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        #expect(AppSettings(defaults: defaults).appIconMode == .menuBar)
    }

    @Test
    @MainActor
    func appIconModePersistsAcrossInstances() throws {
        let suiteName = "AppSettingsAppIconModeTests.persist"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        AppSettings(defaults: defaults).appIconMode = .hidden

        #expect(AppSettings(defaults: defaults).appIconMode == .hidden)
    }

    @Test
    @MainActor
    func appIconModeFallsBackToMenuBarForUnknownValue() throws {
        let suiteName = "AppSettingsAppIconModeTests.unknown"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("tray", forKey: "appIconMode")

        #expect(AppSettings(defaults: defaults).appIconMode == .menuBar)
    }
}

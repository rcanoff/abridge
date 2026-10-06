@testable import ABridge
import AppKit
import Foundation
import Testing

@Suite("AppPresentationStore")
struct AppPresentationStoreTests {
    @Test(arguments: [
        (AppIconMode.menuBar, false, true, NSApplication.ActivationPolicy.accessory),
        (AppIconMode.menuBar, true, true, NSApplication.ActivationPolicy.accessory),
        (AppIconMode.dock, false, false, NSApplication.ActivationPolicy.regular),
        (AppIconMode.dock, true, false, NSApplication.ActivationPolicy.regular),
        (AppIconMode.hidden, false, false, NSApplication.ActivationPolicy.accessory),
        (AppIconMode.hidden, true, false, NSApplication.ActivationPolicy.regular),
    ])
    @MainActor
    func modeAndSettingsWindowDriveIcons(
        mode: AppIconMode,
        settingsWindowOpen: Bool,
        expectedMenuBarIcon: Bool,
        expectedPolicy: NSApplication.ActivationPolicy
    ) throws {
        let (store, applier) = try makeStore(
            suiteName: "AppPresentationStoreTests.table.\(mode.rawValue).\(settingsWindowOpen)"
        )
        store.setAppIconMode(mode)

        if settingsWindowOpen {
            store.settingsWindowDidOpen()
        } else {
            store.settingsWindowDidOpen()
            store.settingsWindowDidClose()
        }

        #expect(store.showsMenuBarIcon == expectedMenuBarIcon)
        #expect(applier.appliedPolicies.last == expectedPolicy)
    }

    @Test
    @MainActor
    func hiddenLaunchOpensSettingsWhenNotLaunchedAtLogin() throws {
        let (store, applier) = try makeStore(suiteName: "AppPresentationStoreTests.hiddenManualLaunch")
        store.appSettings.appIconMode = .hidden
        store.appSettings.launchAtLogin = false

        store.applyLaunchPresentation()

        #expect(store.settingsWindowRequest == 1)
        #expect(applier.appliedPolicies == [.accessory])
    }

    @Test
    @MainActor
    func hiddenLaunchStaysSilentWhenLaunchAtLoginIsEnabled() throws {
        let (store, _) = try makeStore(suiteName: "AppPresentationStoreTests.hiddenLoginLaunch")
        store.appSettings.appIconMode = .hidden
        store.appSettings.launchAtLogin = true

        store.applyLaunchPresentation()

        #expect(store.settingsWindowRequest == 0)
    }

    @Test(arguments: [AppIconMode.menuBar, .dock])
    @MainActor
    func visibleModesDoNotOpenSettingsAtLaunch(mode: AppIconMode) throws {
        let (store, applier) = try makeStore(suiteName: "AppPresentationStoreTests.launch.\(mode.rawValue)")
        store.appSettings.appIconMode = mode

        store.applyLaunchPresentation()

        #expect(store.settingsWindowRequest == 0)
        #expect(applier.appliedPolicies == [mode.activationPolicy(isSettingsWindowOpen: false)])
    }

    @Test
    @MainActor
    func changingModeWithSettingsOpenBringsSettingsBackToFront() throws {
        let (store, applier) = try makeStore(suiteName: "AppPresentationStoreTests.changeWhileOpen")
        store.setAppIconMode(.dock)
        store.settingsWindowDidOpen()
        let requestsBefore = store.settingsWindowRequest

        store.setAppIconMode(.menuBar)

        #expect(store.settingsWindowRequest == requestsBefore + 1)
        #expect(applier.appliedPolicies.last == .accessory)
    }

    @Test
    @MainActor
    func changingModeWithSettingsClosedDoesNotOpenSettings() throws {
        let (store, applier) = try makeStore(suiteName: "AppPresentationStoreTests.changeWhileClosed")

        store.setAppIconMode(.dock)

        #expect(store.settingsWindowRequest == 0)
        #expect(applier.appliedPolicies == [.regular])
    }

    @MainActor
    private func makeStore(suiteName: String) throws -> (AppPresentationStore, MockActivationPolicyApplier) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let applier = MockActivationPolicyApplier()
        let store = AppPresentationStore(appSettings: AppSettings(defaults: defaults), activationPolicyApplier: applier)
        return (store, applier)
    }
}

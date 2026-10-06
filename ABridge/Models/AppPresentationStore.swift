import AppKit
import Observation

/// Drives the menu bar icon, the Dock icon, and Settings window requests from `AppSettings.appIconMode`.
@Observable
@MainActor
final class AppPresentationStore {
    let appSettings: AppSettings

    private(set) var isSettingsWindowOpen = false
    /// Bumped to ask the app scene to open the Settings window or bring it to front.
    private(set) var settingsWindowRequest = 0

    @ObservationIgnored private let activationPolicyApplier: any AppActivationPolicyApplying

    init(
        appSettings: AppSettings,
        activationPolicyApplier: any AppActivationPolicyApplying = NSApplicationActivationPolicyApplier()
    ) {
        self.appSettings = appSettings
        self.activationPolicyApplier = activationPolicyApplier
    }

    var showsMenuBarIcon: Bool {
        appSettings.appIconMode.showsMenuBarIcon
    }

    /// Applies the Dock icon for the saved mode. Hidden mode opens Settings unless the launch came from login.
    func applyLaunchPresentation() {
        applyActivationPolicy()
        if appSettings.appIconMode == .hidden, !appSettings.launchAtLogin {
            requestSettingsWindow()
        }
    }

    func setAppIconMode(_ mode: AppIconMode) {
        guard mode != appSettings.appIconMode else { return }
        appSettings.appIconMode = mode
        applyActivationPolicy()
        // Leaving `.regular` deactivates the app; bring Settings back to front.
        if isSettingsWindowOpen {
            requestSettingsWindow()
        }
    }

    func requestSettingsWindow() {
        settingsWindowRequest += 1
    }

    func settingsWindowDidOpen() {
        isSettingsWindowOpen = true
        applyActivationPolicy()
    }

    func settingsWindowDidClose() {
        isSettingsWindowOpen = false
        applyActivationPolicy()
    }

    private func applyActivationPolicy() {
        activationPolicyApplier.apply(
            appSettings.appIconMode.activationPolicy(isSettingsWindowOpen: isSettingsWindowOpen)
        )
    }
}

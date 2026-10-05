import AppKit
import Observation
import Sparkle

/// Owns Sparkle's standard updater and the update state the menu bar shows.
///
/// Apple Bridge is a menu bar agent, so scheduled update alerts would otherwise open behind other apps.
/// Outside the launch window the update is surfaced in the menu instead (Sparkle gentle reminders).
@Observable
@MainActor
final class SparkleUpdaterService: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var canCheckForUpdates = false
    /// Display version of a scheduled update waiting for the user to open it from the menu.
    private(set) var pendingUpdateVersion: String?

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(startsUpdater: Bool) {
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
        updaterController = controller
    }

    func checkForUpdates() {
        NSApp.activate()
        updaterController?.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        pendingUpdateVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        pendingUpdateVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingUpdateVersion = nil
    }
}

import AppKit

/// AppKit lifecycle hooks SwiftUI scenes do not expose. Dependencies arrive through `configure` because
/// `NSApplicationDelegateAdaptor` creates the delegate with no arguments.
@MainActor
final class ABridgeAppDelegate: NSObject, NSApplicationDelegate {
    private var presentationStore: AppPresentationStore?
    private var serverStore: ServerStore?

    func configure(presentationStore: AppPresentationStore, serverStore: ServerStore) {
        self.presentationStore = presentationStore
        self.serverStore = serverStore
    }

    func applicationDidFinishLaunching(_: Notification) {
        presentationStore?.applyLaunchPresentation()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad, Dock click) shows Settings in every mode.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        presentationStore?.requestSettingsWindow()
        return false
    }

    /// The app keeps serving MCP after Settings closes, including in Dock mode.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let serverStore else { return .terminateNow }
        return AppQuitCoordinator.handleTerminationRequest(serverStore: serverStore) { shouldTerminate in
            NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
        }
    }
}

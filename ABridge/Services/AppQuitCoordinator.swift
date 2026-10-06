import AppKit

enum AppQuitCoordinator {
    /// Every quit path (menu bar Quit, Cmd-Q, app menu, Dock) reaches `applicationShouldTerminate`,
    /// which lands here: stop the MCP server, then let the app terminate.
    @MainActor
    static func handleTerminationRequest(
        serverStore: ServerStore,
        reply: @escaping @MainActor (Bool) -> Void
    ) -> NSApplication.TerminateReply {
        guard !isQuitDisabled(serverStore: serverStore) else { return .terminateCancel }
        Task { @MainActor in
            await serverStore.stopServer()
            reply(true)
        }
        return .terminateLater
    }

    @MainActor
    static func isQuitDisabled(serverStore: ServerStore) -> Bool {
        isQuitDisabled(runState: serverStore.runState, isStarting: serverStore.isStarting)
    }

    static func isQuitDisabled(runState: ServerRunState, isStarting: Bool) -> Bool {
        runState == .starting || isStarting
    }
}

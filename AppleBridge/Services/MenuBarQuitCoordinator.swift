import Foundation

enum MenuBarQuitCoordinator {
    @MainActor
    static func quit(serverStore: ServerStore, appQuitter: any AppQuitting) async {
        await serverStore.stopServer()
        appQuitter.terminate()
    }

    @MainActor
    static func isQuitDisabled(serverStore: ServerStore) -> Bool {
        isQuitDisabled(runState: serverStore.runState, isStarting: serverStore.isStarting)
    }

    static func isQuitDisabled(runState: ServerRunState, isStarting: Bool) -> Bool {
        runState == .starting || isStarting
    }
}
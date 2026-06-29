@testable import AppleBridge
import Foundation
import Testing

@Suite("MenuBarQuit")
struct MenuBarQuitTests {
    @Test
    @MainActor
    func quitStopsRunningServerThenTerminates() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let quitter = MockAppQuitter()

        await MenuBarQuitCoordinator.quit(serverStore: serverStore, appQuitter: quitter)

        #expect(await mock.stopCallCount == 1)
        #expect(quitter.terminateCallCount == 1)
        #expect(serverStore.runState == .stopped)
    }

    @Test
    @MainActor
    func quitTerminatesImmediatelyWhenServerAlreadyStopped() async {
        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let quitter = MockAppQuitter()

        await MenuBarQuitCoordinator.quit(serverStore: serverStore, appQuitter: quitter)

        #expect(await mock.stopCallCount == 1)
        #expect(quitter.terminateCallCount == 1)
    }

    @Test
    @MainActor
    func quitStillTerminatesAfterStopFailure() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        await mock.setStartError(nil)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        await mock.setStopError(ServerOperationError(message: "stop failed"))
        let quitter = MockAppQuitter()

        await MenuBarQuitCoordinator.quit(serverStore: serverStore, appQuitter: quitter)

        #expect(await mock.stopCallCount == 1)
        #expect(quitter.terminateCallCount == 1)
    }

    @Test
    func isQuitDisabledWhileRunStateIsStarting() {
        #expect(MenuBarQuitCoordinator.isQuitDisabled(runState: .starting, isStarting: false))
    }

    @Test
    func isQuitDisabledWhileIsStartingFlagIsSet() {
        #expect(MenuBarQuitCoordinator.isQuitDisabled(runState: .stopped, isStarting: true))
    }

    @Test
    func isQuitEnabledWhenServerIsIdle() {
        #expect(MenuBarQuitCoordinator.isQuitDisabled(runState: .stopped, isStarting: false) == false)
        #expect(MenuBarQuitCoordinator.isQuitDisabled(runState: .running, isStarting: false) == false)
    }
}
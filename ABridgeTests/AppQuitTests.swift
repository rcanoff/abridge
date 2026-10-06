@testable import ABridge
import AppKit
import Foundation
import Testing

@Suite("AppQuit")
struct AppQuitTests {
    @Test
    @MainActor
    func terminationRequestStopsRunningServerBeforeReplying() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        let (replies, continuation) = AsyncStream.makeStream(of: (Bool, ServerRunState).self)

        let decision = AppQuitCoordinator.handleTerminationRequest(serverStore: serverStore) { shouldTerminate in
            continuation.yield((shouldTerminate, serverStore.runState))
            continuation.finish()
        }

        #expect(decision == .terminateLater)
        var iterator = replies.makeAsyncIterator()
        let reply = await iterator.next()
        #expect(reply?.0 == true)
        #expect(reply?.1 == .stopped)
        #expect(await mock.stopCallCount == 1)
    }

    @Test
    @MainActor
    func terminationRequestStillQuitsAfterStopFailure() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.startServer(port: 3020, enabledCapabilities: [])
        await mock.setStopError(ServerOperationError(message: "stop failed"))
        let (replies, continuation) = AsyncStream.makeStream(of: Bool.self)

        let decision = AppQuitCoordinator.handleTerminationRequest(serverStore: serverStore) { shouldTerminate in
            continuation.yield(shouldTerminate)
            continuation.finish()
        }

        #expect(decision == .terminateLater)
        var iterator = replies.makeAsyncIterator()
        #expect(await iterator.next() == true)
        #expect(await mock.stopCallCount == 1)
    }

    @Test
    @MainActor
    func terminationRequestIsCancelledWhileServerIsStarting() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.starting)
        let serverStore = ServerStore(serverService: mock)
        await serverStore.refreshStatus()

        let decision = AppQuitCoordinator.handleTerminationRequest(serverStore: serverStore) { _ in
            Issue.record("Reply must not be sent for a cancelled termination")
        }

        #expect(decision == .terminateCancel)
        #expect(await mock.stopCallCount == 0)
    }

    @Test
    func isQuitDisabledWhileRunStateIsStarting() {
        #expect(AppQuitCoordinator.isQuitDisabled(runState: .starting, isStarting: false))
    }

    @Test
    func isQuitDisabledWhileIsStartingFlagIsSet() {
        #expect(AppQuitCoordinator.isQuitDisabled(runState: .stopped, isStarting: true))
    }

    @Test
    func isQuitEnabledWhenServerIsIdle() {
        #expect(AppQuitCoordinator.isQuitDisabled(runState: .stopped, isStarting: false) == false)
        #expect(AppQuitCoordinator.isQuitDisabled(runState: .running, isStarting: false) == false)
    }

    @Test
    @MainActor
    func defaultLaunchDependenciesUseProductionAppQuitter() {
        let dependencies = ABridgeApp.makeDefaultLaunchDependencies()

        #expect(dependencies.appQuitter is NSApplicationQuitter)
    }
}

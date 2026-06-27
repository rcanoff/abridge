@testable import AppleBridge
import Foundation
import Testing

@Suite("ServerStore")
struct ServerStoreTests {
    @Test
    @MainActor
    func refreshStatusMapsRunning() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let store = ServerStore(serverService: mock)

        await store.refreshStatus()

        #expect(store.runState == .running)
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func refreshStatusMapsStopped() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.stopped)
        let store = ServerStore(serverService: mock)

        await store.refreshStatus()

        #expect(store.runState == .stopped)
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func startServerSuccessUpdatesRunningState() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        await mock.setBearerTokenResult("started-token")
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: [])

        #expect(store.runState == .running)
        #expect(store.isStarting == false)
        #expect(store.lastError == nil)
        #expect(store.bearerToken == "started-token")
        #expect(await mock.startCallCount == 1)
        #expect(await mock.lastStartHost == "127.0.0.1")
        #expect(await mock.lastStartPort == 3020)
    }

    @Test
    @MainActor
    func startServerFailureSetsLastError() async {
        let mock = MockServerService()
        await mock.setStartError(ServerOperationError(message: "failed to bind server: port in use"))
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: [])

        #expect(store.lastError == "failed to bind server: port in use")
        #expect(store.isStarting == false)
        #expect(store.runState == .error("failed to bind server: port in use"))
    }

    @Test
    @MainActor
    func stopServerClearsRunningState() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let store = ServerStore(serverService: mock)
        await store.startServer(port: 3020, enabledCapabilities: [])

        await store.stopServer()

        #expect(store.runState == .stopped)
        #expect(store.lastError == nil)
        #expect(await mock.stopCallCount == 1)
    }

    @Test
    @MainActor
    func refreshBearerTokenLoadsFromService() async {
        let mock = MockServerService()
        await mock.setBearerTokenResult("display-token")
        let store = ServerStore(serverService: mock)

        await store.refreshBearerToken()

        #expect(store.bearerToken == "display-token")
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func resetBearerTokenRestartsWhenRunning() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        await mock.setBearerTokenResult("token-before-reset")
        let store = ServerStore(serverService: mock)
        await store.startServer(port: 3020, enabledCapabilities: [])

        await store.resetBearerToken(port: 3020, enabledCapabilities: [], restartIfRunning: true)

        #expect(store.runState == .running)
        #expect(store.bearerToken == "rotated-token-before-reset")
        #expect(await mock.startCallCount == 2)
    }

    @Test
    @MainActor
    func refreshStatusPreservesStartupErrorWhenServiceReportsStopped() async {
        let mock = MockServerService()
        await mock.setStartError(ServerOperationError(message: "failed to bind server: port in use"))
        await mock.setRefreshResult(.stopped)
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: [])

        #expect(store.runState == .error("failed to bind server: port in use"))
        #expect(store.lastError == "failed to bind server: port in use")

        await store.refreshStatus()

        #expect(store.runState == .error("failed to bind server: port in use"))
        #expect(store.lastError == "failed to bind server: port in use")
    }

    @Test
    @MainActor
    func stopServerClearsStartupErrorState() async {
        let mock = MockServerService()
        await mock.setStartError(ServerOperationError(message: "failed to bind server: port in use"))
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: [])

        await store.stopServer()

        #expect(store.runState == .stopped)
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func startServerGuardsDoubleStartWhileRunning() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.running)
        let store = ServerStore(serverService: mock)
        await store.startServer(port: 3020, enabledCapabilities: [])

        await store.startServer(port: 3020, enabledCapabilities: [])

        #expect(await mock.startCallCount == 1)
    }
}

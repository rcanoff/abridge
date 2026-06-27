import Foundation
import Testing
@testable import AppleBridge

@Suite("ServerStore")
struct ServerStoreTests {
    @Test
    @MainActor
    func refreshStatusMapsRunning() {
        let mock = MockServerService()
        mock.refreshResult = .running
        let store = ServerStore(serverService: mock)

        store.refreshStatus()

        #expect(store.runState == .running)
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func refreshStatusMapsStopped() {
        let mock = MockServerService()
        mock.refreshResult = .stopped
        let store = ServerStore(serverService: mock)

        store.refreshStatus()

        #expect(store.runState == .stopped)
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func startServerSuccessUpdatesRunningState() {
        let mock = MockServerService()
        mock.refreshResult = .running
        let store = ServerStore(serverService: mock)

        store.startServer()

        #expect(store.runState == .running)
        #expect(store.isStarting == false)
        #expect(store.lastError == nil)
        #expect(mock.startCallCount == 1)
        #expect(mock.lastStartHost == "127.0.0.1")
        #expect(mock.lastStartPort == 3020)
    }

    @Test
    @MainActor
    func startServerFailureSetsLastError() {
        let mock = MockServerService()
        mock.startError = ServerOperationError(message: "failed to bind server: port in use")
        let store = ServerStore(serverService: mock)

        store.startServer()

        #expect(store.lastError == "failed to bind server: port in use")
        #expect(store.isStarting == false)
        #expect(store.runState == .error("failed to bind server: port in use"))
    }

    @Test
    @MainActor
    func stopServerClearsRunningState() {
        let mock = MockServerService()
        mock.refreshResult = .running
        let store = ServerStore(serverService: mock)
        store.startServer()

        store.stopServer()

        #expect(store.runState == .stopped)
        #expect(store.lastError == nil)
        #expect(mock.stopCallCount == 1)
    }

    @Test
    @MainActor
    func startServerGuardsDoubleStartWhileRunning() {
        let mock = MockServerService()
        mock.refreshResult = .running
        let store = ServerStore(serverService: mock)
        store.startServer()

        store.startServer()

        #expect(mock.startCallCount == 1)
    }

}
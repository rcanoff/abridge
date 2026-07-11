@testable import AppleBridge
import Foundation
import SwiftUI
import Testing

@Suite("MenuBarNativeMenu")
struct MenuBarNativeMenuTests {
    @Test(arguments: [
        (ServerRunState.running, "MCP Server Running"),
        (ServerRunState.stopped, "MCP Server Stopped"),
        (ServerRunState.starting, "MCP Server Starting…"),
        (ServerRunState.error("bind failed"), "MCP Server Error"),
    ])
    func statusLabelMapsRunState(runState: ServerRunState, expectedLabel: String) {
        #expect(MenuBarMCPStatusFormatting.statusLabel(for: runState) == expectedLabel)
    }

    @Test
    func statusColorForRunningIsGreen() {
        #expect(MenuBarMCPStatusFormatting.statusColor(for: .running) == .green)
    }

    @Test
    func statusColorForStoppedIsRed() {
        #expect(MenuBarMCPStatusFormatting.statusColor(for: .stopped) == .red)
    }

    @Test
    func statusColorForStartingIsYellow() {
        #expect(MenuBarMCPStatusFormatting.statusColor(for: .starting) == .yellow)
    }

    @Test(arguments: [ServerRunState.error("timeout"), ServerRunState.error("")])
    func statusColorForErrorIsRed(runState: ServerRunState) {
        #expect(MenuBarMCPStatusFormatting.statusColor(for: runState) == .red)
    }

    @Test
    func endpointURLUsesConfiguredPort() {
        #expect(MenuBarEndpointFormatting.endpointURL(port: 4242) == "http://127.0.0.1:4242/mcp")
    }

    @Test
    @MainActor
    func quitIsDisabledWhenServerStoreReportsStarting() async {
        let mock = MockServerService()
        await mock.setRefreshResult(.starting)
        let serverStore = ServerStore(serverService: mock)

        await serverStore.refreshStatus()

        #expect(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore))
    }

    @Test
    @MainActor
    func quitIsDisabledWhileServerStoreIsStartingServer() async {
        let mock = MockServerService()
        let startEntered = await mock.enableStartHold()
        await mock.setRefreshResult(.running)
        let serverStore = ServerStore(serverService: mock)
        let startTask = Task { await serverStore.startServer(port: 3020, enabledCapabilities: []) }

        for await _ in startEntered {
            #expect(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore))
            break
        }

        await mock.releaseHeldStart()
        await startTask.value
        #expect(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore) == false)
    }

    @Test(arguments: [ServerRunState.stopped, ServerRunState.running])
    @MainActor
    func quitIsEnabledWhenServerStoreIsIdle(runState: ServerRunState) async {
        let mock = MockServerService()
        await mock.setRefreshResult(runState)
        let serverStore = ServerStore(serverService: mock)

        await serverStore.refreshStatus()

        #expect(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore) == false)
    }
}

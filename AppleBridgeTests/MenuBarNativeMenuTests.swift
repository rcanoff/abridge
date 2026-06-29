@testable import AppleBridge
import Foundation
import SwiftUI
import Testing

@Suite("MenuBarNativeMenu")
struct MenuBarNativeMenuTests {
    @Test(arguments: [
        (ServerRunState.running, "● MCP Server Running"),
        (ServerRunState.stopped, "● MCP Server Stopped"),
        (ServerRunState.starting, "● MCP Server Starting…"),
        (ServerRunState.error("bind failed"), "● MCP Server Error"),
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
}
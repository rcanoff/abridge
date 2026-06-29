import SwiftUI

enum MenuBarMCPStatusFormatting {
    static func statusLabel(for runState: ServerRunState) -> String {
        switch runState {
        case .running:
            "● MCP Server Running"
        case .stopped:
            "● MCP Server Stopped"
        case .starting:
            "● MCP Server Starting…"
        case .error:
            "● MCP Server Error"
        }
    }

    static func statusColor(for runState: ServerRunState) -> Color {
        switch runState {
        case .running:
            .green
        case .stopped:
            .red
        case .starting:
            .yellow
        case .error:
            .red
        }
    }

    static func statusUsesSecondaryAccent(for runState: ServerRunState) -> Bool {
        switch runState {
        case .stopped, .starting:
            true
        case .running, .error:
            false
        }
    }
}

enum MenuBarEndpointFormatting {
    static func endpointURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }
}

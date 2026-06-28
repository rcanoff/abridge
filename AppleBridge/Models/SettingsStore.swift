import Foundation
import Observation

enum SettingsTab: String, CaseIterable, Identifiable {
    case mcp
    case permissions

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .mcp:
            "MCP"
        case .permissions:
            "Permissions"
        }
    }
}

@Observable
@MainActor
final class SettingsStore {
    var selectedTab: SettingsTab = .mcp
    private(set) var tokenResetNotice: String?

    let appSettings: AppSettings

    private let serverStore: ServerStore
    private var didPerformLaunchRestore = false

    init(appSettings: AppSettings, serverStore: ServerStore) {
        self.appSettings = appSettings
        self.serverStore = serverStore
    }

    var endpointURL: String {
        "http://127.0.0.1:\(appSettings.mcpPort)/mcp"
    }

    func applyMCPEnabledChange(_ enabled: Bool) async {
        appSettings.mcpEnabled = enabled
        tokenResetNotice = nil

        if enabled {
            await serverStore.startServer(
                port: appSettings.mcpPort,
                enabledCapabilities: appSettings.enabledMCPCapabilityIDs
            )
        } else {
            await serverStore.stopServer()
        }
    }

    func applyPortChange(_ port: UInt16) async {
        guard port != appSettings.mcpPort else { return }

        appSettings.mcpPort = port
        tokenResetNotice = nil

        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: port,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs
        )
    }

    func copyBearerToken() -> String? {
        serverStore.bearerToken
    }

    func resetBearerToken() async {
        tokenResetNotice = nil
        let wasRunning = serverStore.runState == .running
        await serverStore.resetBearerToken(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs,
            restartIfRunning: appSettings.mcpEnabled
        )
        guard serverStore.lastError == nil else { return }
        tokenResetNotice = tokenResetNoticeMessage(
            mcpEnabled: appSettings.mcpEnabled,
            wasRunning: wasRunning
        )
    }

    func applySavedCapabilities(remindersAuthorized: Bool) async {
        tokenResetNotice = nil
        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: remindersAuthorized
            )
        )
    }

    private func tokenResetNoticeMessage(mcpEnabled: Bool, wasRunning: Bool) -> String {
        if mcpEnabled, wasRunning {
            "Server restarted with a new token. Update your MCP client."
        } else {
            "Bearer token reset. Update your MCP client with the new token."
        }
    }

    /// Restores the MCP server once per process launch when `mcpEnabled` was persisted.
    /// Invoked from `AppleBridgeApp.init()` only — not from any SwiftUI view lifecycle.
    func performLaunchRestoreIfNeeded() async {
        guard !didPerformLaunchRestore else { return }
        didPerformLaunchRestore = true

        guard appSettings.mcpEnabled else { return }

        await serverStore.startServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs
        )
    }
}

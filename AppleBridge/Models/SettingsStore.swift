import Foundation
import Observation

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case mcp
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mcp:
            return "MCP"
        case .permissions:
            return "Permissions"
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
        tokenResetNotice = "Server will restart with a new token. Update your MCP client."
        await serverStore.resetBearerToken(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs,
            restartIfRunning: appSettings.mcpEnabled
        )
    }

    func applySavedCapabilities() async {
        tokenResetNotice = nil
        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs
        )
    }

    func restoreServerOnLaunchIfNeeded() async {
        guard appSettings.mcpEnabled else { return }

        await serverStore.startServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.enabledMCPCapabilityIDs
        )
    }
}
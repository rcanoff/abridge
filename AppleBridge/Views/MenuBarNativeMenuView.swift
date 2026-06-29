import AppKit
import SwiftUI

struct MenuBarNativeMenuView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var serverStore: ServerStore
    @Bindable var settingsStore: SettingsStore
    private let appQuitter: any AppQuitting

    init(
        serverStore: ServerStore,
        settingsStore: SettingsStore,
        appQuitter: any AppQuitting
    ) {
        self.serverStore = serverStore
        self.settingsStore = settingsStore
        self.appQuitter = appQuitter
    }

    var body: some View {
        Button("Open Apple Bridge") {
            openSettings()
        }

        Divider()

        Button {} label: {
            statusLabel
        }
        .disabled(true)

        Button("Copy MCP Endpoint") {
            copyEndpoint()
        }

        Divider()

        Button("Quit Apple Bridge") {
            Task { @MainActor in
                await MenuBarQuitCoordinator.quit(serverStore: serverStore, appQuitter: appQuitter)
            }
        }
        .disabled(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore))
    }

    @ViewBuilder
    private var statusLabel: some View {
        let runState = serverStore.runState
        let label = MenuBarMCPStatusFormatting.statusLabel(for: runState)
        let color = MenuBarMCPStatusFormatting.statusColor(for: runState)

        if MenuBarMCPStatusFormatting.statusUsesSecondaryAccent(for: runState) {
            Text(label)
                .foregroundStyle(color, .secondary)
        } else {
            Text(label)
                .foregroundStyle(color)
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    private func copyEndpoint() {
        let endpoint = MenuBarEndpointFormatting.endpointURL(port: settingsStore.appSettings.mcpPort)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint, forType: .string)
    }
}
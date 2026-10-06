import AppKit
import SwiftUI

struct MenuBarNativeMenuView: View {
    @Bindable var serverStore: ServerStore
    @Bindable var settingsStore: SettingsStore
    let presentationStore: AppPresentationStore
    let updaterService: SparkleUpdaterService
    let appQuitter: any AppQuitting

    var body: some View {
        Button("Open ABridge") {
            presentationStore.requestSettingsWindow()
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

        Button(updateMenuTitle) {
            updaterService.checkForUpdates()
        }
        .disabled(!updaterService.canCheckForUpdates)

        Button("Quit ABridge") {
            appQuitter.terminate()
        }
        .disabled(AppQuitCoordinator.isQuitDisabled(serverStore: serverStore))
    }

    private var updateMenuTitle: String {
        if let version = updaterService.pendingUpdateVersion {
            "Update to \(version)…"
        } else {
            "Check for Updates…"
        }
    }

    private var statusLabel: some View {
        let runState = serverStore.runState
        let label = MenuBarMCPStatusFormatting.statusLabel(for: runState)
        let color = MenuBarMCPStatusFormatting.statusColor(for: runState)

        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(label)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private func copyEndpoint() {
        let endpoint = MenuBarEndpointFormatting.endpointURL(port: settingsStore.appSettings.mcpPort)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint, forType: .string)
    }
}

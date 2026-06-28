import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var store: AppStore
    @Bindable var serverStore: ServerStore

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.popoverSpacing) {
            Text("Apple Bridge")
                .font(.headline)

            LabeledContent("Reminders Access") {
                PermissionStatusIndicator(status: store.permissionStatus)
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.permissionStatus == .notDetermined || store.permissionStatus == .writeOnly {
                Button("Grant Access") {
                    Task { await store.requestAccess() }
                }
                .disabled(store.isRequestingPermission)
            }

            if store.permissionStatus == .denied {
                Button("Open System Settings") {
                    store.openRemindersPrivacySettings()
                }
            }

            if store.isRequestingPermission {
                ProgressView()
                    .controlSize(.small)
            }

            Divider()

            LabeledContent("Server") {
                ServerStatusIndicator(state: serverStore.runState)
            }

            if let lastError = serverStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

            if isServerStarting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 260)
        .presentationBackground {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: SettingsDesign.glassCornerRadius))
        }
    }

    private var isServerStarting: Bool {
        serverStore.runState == .starting || serverStore.isStarting
    }
}

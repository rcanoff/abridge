import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var store: AppStore
    @Bindable var serverStore: ServerStore
    private let appQuitter: any AppQuitting

    init(
        store: AppStore,
        serverStore: ServerStore,
        appQuitter: any AppQuitting = NSApplicationQuitter()
    ) {
        self.store = store
        self.serverStore = serverStore
        self.appQuitter = appQuitter
    }

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

            Button("Quit Apple Bridge") {
                Task { await MenuBarQuitCoordinator.quit(serverStore: serverStore, appQuitter: appQuitter) }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore))

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
        MenuBarQuitCoordinator.isQuitDisabled(serverStore: serverStore)
    }
}

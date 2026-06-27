import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var store: AppStore
    @Bindable var serverStore: ServerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Bridge")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders Access")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(store.permissionStatus.displayName)
                    .font(.body)
                    .foregroundStyle(permissionStatusColor)
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.permissionStatus == .notDetermined {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(serverStore.runState.displayName)
                    .font(.body)
                    .foregroundStyle(serverStatusColor)
            }

            if let lastError = serverStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Button("Settings…") {
                openWindow(id: "settings")
            }

            if isServerStarting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var permissionStatusColor: Color {
        switch store.permissionStatus {
        case .authorized:
            return .green
        case .notDetermined, .unknown:
            return .orange
        case .denied, .restricted:
            return .red
        }
    }

    private var serverStatusColor: Color {
        switch serverStore.runState {
        case .running:
            return .green
        case .starting:
            return .orange
        case .stopped:
            return .secondary
        case .error:
            return .red
        }
    }

    private var isServerStarting: Bool {
        serverStore.runState == .starting || serverStore.isStarting
    }
}
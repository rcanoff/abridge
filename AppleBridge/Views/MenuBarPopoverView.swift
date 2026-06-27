import SwiftUI

struct MenuBarPopoverView: View {
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

                Text("\(serverStore.host):\(serverStore.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let bearerToken = serverStore.bearerToken {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bearer Token")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(bearerToken)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }

            if let lastError = serverStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            serverControlButton

            if isServerStarting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 260)
    }

    @ViewBuilder
    private var serverControlButton: some View {
        switch serverStore.runState {
        case .stopped, .error:
            Button("Start Server") {
                Task { await serverStore.startServer() }
            }
            .disabled(serverStore.isStarting)
        case .running:
            Button("Stop Server") {
                Task { await serverStore.stopServer() }
            }
        case .starting:
            Button("Start Server") {}
                .disabled(true)
        }
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
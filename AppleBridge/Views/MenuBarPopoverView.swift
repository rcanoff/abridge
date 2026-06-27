import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var store: AppStore

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
                    .foregroundStyle(statusColor)
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
                    openRemindersPrivacySettings()
                }
            }

            if store.isRequestingPermission {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        switch store.permissionStatus {
        case .authorized:
            return .green
        case .notDetermined, .unknown:
            return .orange
        case .denied, .restricted:
            return .red
        }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
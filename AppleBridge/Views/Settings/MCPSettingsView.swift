import AppKit
import SwiftUI

struct MCPSettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var serverStore: ServerStore

    @State private var portText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MCP")
                    .font(.title2)
                    .fontWeight(.bold)

                GroupBox {
                    Toggle("Enable server", isOn: mcpEnabledBinding)
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(serverStore.runState.displayName)
                        }
                    }
                }

                GroupBox {
                    LabeledContent("Host", value: serverStore.host)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("3020", text: $portText)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(applyPortChange)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Endpoint")
                            .foregroundStyle(.secondary)
                        Text(settingsStore.endpointURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bearer token")
                            .foregroundStyle(.secondary)

                        if let token = serverStore.bearerToken {
                            Text(token)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                        } else {
                            Text("Not loaded")
                                .foregroundStyle(.secondary)
                        }

                        Text("Used by MCP clients. Never share outside this machine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Copy") {
                                copyToken()
                            }
                            .disabled(serverStore.bearerToken == nil)

                            Button("Reset token", role: .destructive) {
                                Task { await settingsStore.resetBearerToken() }
                            }
                        }

                        if let notice = settingsStore.tokenResetNotice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let lastError = serverStore.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            portText = String(settingsStore.appSettings.mcpPort)
            Task { await serverStore.refreshBearerToken() }
        }
        .onChange(of: settingsStore.appSettings.mcpPort) { _, newValue in
            portText = String(newValue)
        }
    }

    private var mcpEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.appSettings.mcpEnabled },
            set: { newValue in
                Task { await settingsStore.applyMCPEnabledChange(newValue) }
            }
        )
    }

    private var statusColor: Color {
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

    private func applyPortChange() {
        guard let port = UInt16(portText), port > 0 else {
            portText = String(settingsStore.appSettings.mcpPort)
            return
        }
        Task { await settingsStore.applyPortChange(port) }
    }

    private func copyToken() {
        guard let token = settingsStore.copyBearerToken() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }
}
import AppKit
import SwiftUI

struct MCPSettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var serverStore: ServerStore

    @State private var portText = ""
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            startupSection
            serverSection
            connectionSection
            authenticationSection
        }
        .formStyle(.grouped)
        .navigationTitle("MCP")
        .onAppear {
            portText = String(settingsStore.appSettings.mcpPort)
            Task { await serverStore.refreshBearerToken() }
        }
        .onChange(of: settingsStore.appSettings.mcpPort) { _, newValue in
            portText = String(newValue)
        }
        .confirmationDialog(
            "Reset bearer token?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset token", role: .destructive) {
                Task { await settingsStore.resetBearerToken() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server will restart with a new token. Update your MCP client.")
        }
        .safeAreaInset(edge: .bottom) {
            if let lastError = serverStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private var startupSection: some View {
        Section {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
        } header: {
            Text("Startup")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Starts ABridge when you log in. MCP server starts only if you left it enabled.")
                if let error = settingsStore.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var serverSection: some View {
        Section("Server") {
            Toggle("Enable server", isOn: mcpEnabledBinding)
            LabeledContent("Status") {
                ServerStatusIndicator(state: serverStore.runState)
            }
        }
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Host", value: serverStore.host)
            LabeledContent("Port") {
                TextField("", text: $portText, prompt: Text("3020"))
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(applyPortChange)
            }
            endpointRow
        } header: {
            Text("Connection")
        } footer: {
            Text("MCP clients connect to the endpoint above on this machine.")
        }
    }

    private var endpointRow: some View {
        LabeledContent("Endpoint") {
            Text(settingsStore.endpointURL)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var authenticationSection: some View {
        Section {
            authenticationContent
        } header: {
            Text("Authentication")
        } footer: {
            Text("Used by MCP clients. Never share outside this machine.")
        }
    }

    private var authenticationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let token = serverStore.bearerToken {
                Text(APIKeyFormatting.maskAPIKey(token))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(3)
            } else {
                Text("Not loaded")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy") {
                    copyToken()
                }
                .disabled(serverStore.bearerToken == nil)

                Button("Reset token", role: .destructive) {
                    showResetConfirmation = true
                }
            }

            if let notice = settingsStore.tokenResetNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.appSettings.launchAtLogin },
            set: { newValue in
                Task { await settingsStore.applyLaunchAtLoginChange(newValue) }
            }
        )
    }

    private var mcpEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.appSettings.mcpEnabled },
            set: { newValue in
                Task { await settingsStore.applyMCPEnabledChange(newValue) }
            }
        )
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

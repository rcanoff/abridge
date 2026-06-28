import SwiftUI

struct PermissionsSettingsView: View {
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var settingsStore: SettingsStore
    @Bindable var appStore: AppStore

    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.bold)

                GroupBox {
                    LabeledContent("MCP", value: permissionsStore.mcpSummaryLine)
                    LabeledContent("Apple", value: permissionsStore.appleSummaryLine)
                }

                GroupBox("EventKit") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Reminders")
                                .font(.headline)
                            Spacer()
                            Text(permissionsStore.remindersAuthorized ? "Apple granted" : "Apple needed")
                                .font(.caption)
                                .foregroundStyle(permissionsStore.remindersAuthorized ? .green : .orange)
                        }

                        Text("Apple = macOS access · MCP = enforced by Apple Bridge")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(CapabilityCatalog.remindersCapabilities) { capability in
                            capabilityRow(capability)
                        }

                        Text("Calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Coming later")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(explanatoryCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(saveButtonTitle) {
                    Task { await savePermissions() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !permissionsStore.hasPendingChanges)
                .frame(maxWidth: .infinity)

                if let lastError = permissionsStore.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            appStore.refreshStatus()
            permissionsStore.reloadFromSettings()
        }
    }

    @ViewBuilder
    private func capabilityRow(_ capability: CapabilityDefinition) -> some View {
        let enforcement = permissionsStore.enforcement(for: capability)

        Toggle(isOn: binding(for: capability.id)) {
            HStack {
                Text(capability.label)
                Spacer()
                enforcementTags(enforcement)
            }
        }
        .padding(.vertical, 2)
        .background(rowBackground(for: enforcement))
    }

    private func binding(for capabilityID: String) -> Binding<Bool> {
        Binding(
            get: { permissionsStore.checkedCapabilityIDs.contains(capabilityID) },
            set: { permissionsStore.setChecked($0, for: capabilityID) }
        )
    }

    private func enforcementTags(_ enforcement: CapabilityEnforcement) -> some View {
        HStack(spacing: 4) {
            tag(enforcement.apple.label, color: appleTagColor(enforcement.apple))
            tag(enforcement.mcp.label, color: mcpTagColor(enforcement.mcp))
        }
        .font(.caption2)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func appleTagColor(_ tag: AppleEnforcementTag) -> Color {
        switch tag {
        case .granted:
            .green
        case .needed:
            .orange
        case .notApplicable:
            .secondary
        }
    }

    private func mcpTagColor(_ tag: MCPEnforcementTag) -> Color {
        switch tag {
        case .active:
            .green
        case .pending:
            .orange
        case .blocked:
            .red
        case .off:
            .secondary
        }
    }

    private func rowBackground(for enforcement: CapabilityEnforcement) -> Color {
        switch enforcement.mcp {
        case .active:
            Color.green.opacity(0.06)
        case .blocked:
            Color.red.opacity(0.05)
        default:
            .clear
        }
    }

    private var saveButtonTitle: String {
        permissionsStore.hasPendingChanges ? "Save changes" : "Save"
    }

    private var explanatoryCopy: String {
        let blocked = CapabilityCatalog.remindersCapabilities
            .filter { !$0.shipped && permissionsStore.checkedCapabilityIDs.contains($0.id) }
            .map(\.label)

        if !blocked.isEmpty {
            return "\(blocked.joined(separator: ", ")) — Apple may grant access, but MCP blocks until shipped."
        }

        if permissionsStore.hasPendingChanges {
            return "Save to update MCP enforcement. Apple access requested only if needed."
        }

        if !permissionsStore.savedCapabilityIDs.isEmpty {
            return "Active capabilities are enforced by MCP. Apple grants coarse access only."
        }

        return "Select capabilities above."
    }

    private func savePermissions() async {
        isSaving = true
        defer { isSaving = false }

        let saved = await permissionsStore.save()
        guard saved else { return }

        await settingsStore.applySavedCapabilities()
    }
}

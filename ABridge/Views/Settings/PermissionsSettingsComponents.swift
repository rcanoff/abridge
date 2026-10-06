import SwiftUI

struct AppleOSAccessActionsRow: View {
    let title: String
    let granted: Bool
    let isDeniedOrRestricted: Bool
    let isRequesting: Bool
    let onRequest: () -> Void
    let onOpenSystemSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(granted ? "Access granted" : "Request access", action: onRequest)
                .disabled(granted || isDeniedOrRestricted || isRequesting)

            Button("Open \(title) System Settings", systemImage: "gearshape.circle", action: onOpenSystemSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open System Settings")
        }
    }
}

struct ProviderCapabilityAdvancedSection: View {
    let groups: [(header: String?, items: [CapabilityDefinition])]
    let showInactiveFootnote: Bool
    let capabilityBinding: (String) -> Binding<Bool>
    let onEnableAll: () -> Void
    let onDisableAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        // Bound DisclosureGroup + tappable label so text and chevron both toggle (macOS stock
        // DisclosureGroup often only activates the chevron for string labels).
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button("Enable all", action: onEnableAll)
                        .buttonStyle(.borderless)
                    Button("Disable all", action: onDisableAll)
                        .buttonStyle(.borderless)
                }

                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if let header = group.header {
                        Text(header)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, 4)
                    }

                    ForEach(group.items) { capability in
                        Toggle(capability.label, isOn: capabilityBinding(capability.id))
                    }
                }

                if showInactiveFootnote {
                    Text("Saved for MCP; tools stay inactive until macOS access is granted.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Customize tools…")
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(isExpanded ? "Collapses the tool list" : "Expands the tool list")
        }
    }
}

struct ProviderPermissionsCard: View {
    let kind: ProviderPermissionKind
    let status: ProviderPermissionStatus
    let checkedShippedCount: Int
    let enableState: ProviderEnableState
    let osAccessTitle: String?
    let osAccessStatusLabel: String
    let osGrantsReadAccess: Bool
    let osIsDeniedOrRestricted: Bool
    let isRequesting: Bool
    let capabilityGroups: [(header: String?, items: [CapabilityDefinition])]
    let capabilityBinding: (String) -> Binding<Bool>
    let onEnableChange: (Bool) -> Void
    let onEnableAll: () -> Void
    let onDisableAll: () -> Void
    let onRequestAccess: () -> Void
    let onOpenSystemSettings: () -> Void
    let calendarSharingStore: CalendarSharingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(kind.title, systemImage: symbolName)
                        .font(.headline)

                    statusLine

                    Text(osSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    useWithMCPToggle

                    if kind.needsOSAccess, let osAccessTitle {
                        HStack(spacing: 8) {
                            if let sharingKind = kind.calendarSharingKind {
                                CalendarSharingButton(
                                    kind: sharingKind,
                                    osGrantsReadAccess: osGrantsReadAccess,
                                    calendarSharingStore: calendarSharingStore
                                )
                            }

                            AppleOSAccessActionsRow(
                                title: osAccessTitle,
                                granted: osGrantsReadAccess,
                                isDeniedOrRestricted: osIsDeniedOrRestricted,
                                isRequesting: isRequesting,
                                onRequest: onRequestAccess,
                                onOpenSystemSettings: onOpenSystemSettings
                            )
                        }
                    }
                }
            }

            ProviderCapabilityAdvancedSection(
                groups: capabilityGroups,
                showInactiveFootnote: showInactiveFootnote,
                capabilityBinding: capabilityBinding,
                onEnableAll: onEnableAll,
                onDisableAll: onDisableAll
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var useWithMCPToggle: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Use with MCP")
                    .font(.subheadline)
                if enableState == .mixed {
                    Text("Custom selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Use with MCP", isOn: useWithMCPBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Use with MCP")
                .accessibilityValue(useWithMCPAccessibilityValue)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
            Text("·")
                .foregroundStyle(.secondary)
            Text(statusDetail)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.label). \(statusDetail)")
    }

    private var useWithMCPBinding: Binding<Bool> {
        Binding(
            get: { enableState != .off },
            set: { onEnableChange($0) }
        )
    }

    private var useWithMCPAccessibilityValue: String {
        switch enableState {
        case .off: "Off"
        case .on: "On"
        case .mixed: "Mixed"
        }
    }

    private var showInactiveFootnote: Bool {
        checkedShippedCount > 0 && kind.needsOSAccess && !osGrantsReadAccess
    }

    private var osSummaryText: String {
        if kind.needsOSAccess, let osAccessTitle {
            return "Apple: \(osAccessTitle) — \(osAccessStatusLabel)"
        }
        return osAccessStatusLabel
    }

    private var statusDetail: String {
        switch status {
        case .notInUse:
            return "Turn on to expose tools to MCP clients."
        case .needsAccess:
            return "Saved for MCP; inactive until macOS access is granted."
        case .blocked:
            return "macOS access denied — open System Settings to fix."
        case .ready:
            let unit = checkedShippedCount == 1 ? "tool" : "tools"
            if kind.needsOSAccess {
                return "\(checkedShippedCount) \(unit) live for MCP."
            }
            return "\(checkedShippedCount) \(unit) enabled."
        }
    }

    private var statusColor: Color {
        switch status {
        case .notInUse: .secondary
        case .needsAccess: .orange
        case .blocked: .red
        case .ready: .green
        }
    }

    private var symbolName: String {
        switch kind {
        case .reminders: "checklist"
        case .calendarsAndEvents: "calendar"
        case .contacts: "person.crop.circle"
        case .mapkit: "mappin.and.ellipse"
        case .vision: "eye"
        }
    }
}

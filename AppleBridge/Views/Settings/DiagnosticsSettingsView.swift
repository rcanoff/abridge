import AppKit
import SwiftUI

struct DiagnosticsSettingsView: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        Form {
            if showsLoggingDisabledBanner {
                Section {
                    Label {
                        Text("Recording is off. Existing entries remain until they rotate out.")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Toggle("Record tool usage", isOn: usageLoggingBinding)
            } header: {
                Text("Logging")
            } footer: {
                Text("Captures operational metadata only. No request payloads or bearer tokens.")
            }

            Section {
                if settingsStore.usageAuditEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "tray")
                    } description: {
                        Text("Usage events appear here when the MCP server is active and logging is enabled.")
                    }
                } else {
                    ForEach(Array(settingsStore.usageAuditEntries.enumerated()), id: \.offset) { _, entry in
                        UsageAuditEntryRow(entry: entry)
                    }
                }
            } header: {
                HStack {
                    Text("Recent Events")
                    Spacer()
                    Button("Refresh") {
                        Task { await settingsStore.refreshUsageAuditEntries() }
                    }
                    Button("Copy") {
                        copyExport()
                    }
                    .disabled(settingsStore.usageAuditEntries.isEmpty)
                }
            } footer: {
                if !settingsStore.usageAuditEntries.isEmpty {
                    Text("Newest events first. Up to 1,000 entries are retained in memory.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
        .onAppear {
            Task { await settingsStore.refreshUsageAuditEntries() }
        }
    }

    private var showsLoggingDisabledBanner: Bool {
        !settingsStore.appSettings.usageLoggingEnabled && !settingsStore.usageAuditEntries.isEmpty
    }

    private var usageLoggingBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.appSettings.usageLoggingEnabled },
            set: { newValue in
                Task { await settingsStore.applyUsageLoggingChange(newValue) }
            }
        )
    }

    private func copyExport() {
        let json = settingsStore.usageAuditExportJSON()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}

private struct UsageAuditEntryRow: View {
    let entry: UsageAuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.timestampUtc)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summaryText)
                    .lineLimit(2)

                Spacer(minLength: 8)

                UsageAuditOutcomeLabel(success: entry.success, durationMs: entry.durationMs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var summaryText: String {
        if let toolName = entry.toolName, !toolName.isEmpty {
            "\(entry.eventType) · \(toolName)"
        } else {
            entry.eventType
        }
    }

    private var accessibilityText: String {
        var parts = [entry.timestampUtc, summaryText]
        parts.append(entry.success ? "Success" : "Failure")
        if let durationMs = entry.durationMs {
            parts.append("\(durationMs) milliseconds")
        }
        return parts.joined(separator: ", ")
    }
}

private struct UsageAuditOutcomeLabel: View {
    let success: Bool
    let durationMs: UInt64?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? .green : .red)
                .accessibilityHidden(true)

            Text(outcomeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var outcomeText: String {
        if let durationMs {
            return success ? "Success · \(durationMs) ms" : "Failure · \(durationMs) ms"
        }
        return success ? "Success" : "Failure"
    }
}
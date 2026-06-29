import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var settingsStore: SettingsStore
    @Bindable var appStore: AppStore
    @State private var calendarReadAuthorized = false

    var body: some View {
        Form {
            Section {
                AppleRemindersPermissionRow(
                    required: permissionsStore.requiresAppleRemindersAccess,
                    granted: appStore.permissionStatus.grantsReadAccess,
                    isRequestingPermission: appStore.isRequestingPermission,
                    onOpenSystemSettings: { appStore.openRemindersPrivacySettings() },
                    onRequestPermissions: { Task { await appStore.requestAccess() } }
                )
                AppleCalendarsPermissionRow(
                    required: permissionsStore.requiresCalendarAccess,
                    granted: appStore.calendarPermissionStatus.grantsReadAccess,
                    isRequestingPermission: appStore.isRequestingCalendarPermission,
                    onOpenSystemSettings: { appStore.openCalendarPrivacySettings() },
                    onRequestPermissions: { Task { await appStore.requestCalendarAccess() } }
                )
                AppleContactsPermissionRow(
                    required: permissionsStore.requiresAppleContactsAccess,
                    granted: appStore.contactsPermissionStatus.grantsReadAccess,
                    isRequestingPermission: appStore.isRequestingContactsPermission,
                    onOpenSystemSettings: { appStore.openContactsPrivacySettings() },
                    onRequestPermissions: { Task { await appStore.requestContactsAccess() } }
                )
            } header: {
                Text("Apple Permissions")
            } footer: {
                Text("To view or revoke what macOS has granted, use System Settings.")
            }

            Section {
                RemindersMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
                CalendarsMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
                EventsMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
                ContactsMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
            } header: {
                Text("MCP Permissions")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onAppear {
            appStore.refreshStatus()
            permissionsStore.reloadFromSettings()
            reapplyCapabilitiesIfCalendarAccessGranted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appStore.refreshStatus()
            reapplyCapabilitiesIfCalendarAccessGranted()
        }
        .onChange(of: appStore.permissionStatus.grantsReadAccess) { _, remindersAuthorized in
            guard remindersAuthorized, permissionsStore.requiresAppleRemindersAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: true,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess
                )
            }
        }
        .onChange(of: appStore.calendarPermissionStatus.grantsReadAccess) { _, eventsAuthorized in
            guard eventsAuthorized, permissionsStore.requiresCalendarAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: true,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess
                )
            }
        }
        .onChange(of: appStore.contactsPermissionStatus.grantsReadAccess) { _, contactsAuthorized in
            guard contactsAuthorized, permissionsStore.requiresAppleContactsAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: true
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lastError = appStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private func binding(for capabilityID: String) -> Binding<Bool> {
        Binding(
            get: { permissionsStore.checkedCapabilityIDs.contains(capabilityID) },
            set: { newValue in
                permissionsStore.setChecked(newValue, for: capabilityID)
                let remindersAuthorized = appStore.permissionStatus.grantsReadAccess
                let eventsAuthorized = appStore.calendarPermissionStatus.grantsReadAccess
                let contactsAuthorized = appStore.contactsPermissionStatus.grantsReadAccess
                guard permissionsStore.shouldApplySavedCapabilitiesAfterToggle(
                    enabling: newValue,
                    capabilityID: capabilityID,
                    remindersAuthorized: remindersAuthorized,
                    eventsAuthorized: eventsAuthorized,
                    contactsAuthorized: contactsAuthorized
                ) else { return }
                Task {
                    await settingsStore.applySavedCapabilities(
                        remindersAuthorized: remindersAuthorized,
                        eventsAuthorized: eventsAuthorized,
                        contactsAuthorized: contactsAuthorized
                    )
                }
            }
        )
    }

    private func reapplyCapabilitiesIfCalendarAccessGranted() {
        let current = appStore.calendarPermissionStatus.grantsReadAccess
        let becameAuthorized = current && !calendarReadAuthorized
        calendarReadAuthorized = current

        guard becameAuthorized, permissionsStore.requiresCalendarAccess else { return }

        Task {
            await settingsStore.applySavedCapabilities(
                remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                eventsAuthorized: true,
                contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess
            )
        }
    }
}

private struct RemindersMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.remindersCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("Reminders")
        }
    }
}

private struct CalendarsMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.calendarsCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("Calendars")
        }
    }
}

private struct EventsMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.eventsCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("Events")
        }
    }
}

private struct ContactsMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.contactsCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("Contacts")
        }
    }
}

private enum SystemSettingsIcon {
    static let image: NSImage = {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 20, height: 20)
            return icon
        }
        return NSImage(systemSymbolName: "gearshape", accessibilityDescription: "System Settings") ?? NSImage()
    }()
}

private struct AppleRemindersPermissionRow: View {
    let required: Bool
    let granted: Bool
    let isRequestingPermission: Bool
    let onOpenSystemSettings: () -> Void
    let onRequestPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reminders Full Access")
                ApplePermissionAccessStatusLabel(required: required, granted: granted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Request Permissions", action: onRequestPermissions)
                    .buttonStyle(.borderless)
                    .disabled(granted || isRequestingPermission)

                Button(action: onOpenSystemSettings) {
                    Image(nsImage: SystemSettingsIcon.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Reminders System Settings")
                .help("Open Reminders System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct AppleCalendarsPermissionRow: View {
    let required: Bool
    let granted: Bool
    let isRequestingPermission: Bool
    let onOpenSystemSettings: () -> Void
    let onRequestPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendars Full Access")
                ApplePermissionAccessStatusLabel(required: required, granted: granted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Request Permissions", action: onRequestPermissions)
                    .buttonStyle(.borderless)
                    .disabled(granted || isRequestingPermission)

                Button(action: onOpenSystemSettings) {
                    Image(nsImage: SystemSettingsIcon.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Calendars System Settings")
                .help("Open Calendars System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct AppleContactsPermissionRow: View {
    let required: Bool
    let granted: Bool
    let isRequestingPermission: Bool
    let onOpenSystemSettings: () -> Void
    let onRequestPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contacts Access")
                ApplePermissionAccessStatusLabel(required: required, granted: granted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Request Permissions", action: onRequestPermissions)
                    .buttonStyle(.borderless)
                    .disabled(granted || isRequestingPermission)

                Button(action: onOpenSystemSettings) {
                    Image(nsImage: SystemSettingsIcon.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Contacts System Settings")
                .help("Open Contacts System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ApplePermissionAccessStatusLabel: View {
    let required: Bool
    let granted: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(presentation.contextLabel)
                .foregroundStyle(presentation.contextColor)
            Text(" · ")
                .foregroundStyle(.secondary)
            Text(presentation.accessLabel)
                .foregroundStyle(presentation.accessColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var presentation: Presentation {
        Presentation(required: required, granted: granted)
    }

    private var accessibilityText: String {
        "\(presentation.contextLabel), \(presentation.accessLabel)"
    }

    private struct Presentation {
        let contextLabel: String
        let accessLabel: String
        let contextColor: Color
        let accessColor: Color

        init(required: Bool, granted: Bool) {
            contextLabel = required ? "Required" : "Not in use"
            accessLabel = granted ? "Granted" : "Not granted"
            contextColor = .secondary

            if required {
                accessColor = granted ? .green : .red
            } else {
                accessColor = .secondary
            }
        }
    }
}
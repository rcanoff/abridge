import AppKit
import SwiftUI

struct RemindersMCPPermissionsGroup: View {
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

struct CalendarsMCPPermissionsGroup: View {
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

struct EventsMCPPermissionsGroup: View {
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

struct ContactsMCPPermissionsGroup: View {
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

struct MapKitMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.mapkitCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("MapKit")
        }
    }
}

enum SystemSettingsIcon {
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

struct AppleRemindersPermissionRow: View {
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

struct AppleCalendarsPermissionRow: View {
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

struct AppleContactsPermissionRow: View {
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

struct AppleLocationPermissionRow: View {
    let required: Bool
    let granted: Bool
    let isRequestingPermission: Bool
    let onOpenSystemSettings: () -> Void
    let onRequestPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Location Access")
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
                .accessibilityLabel("Open Location System Settings")
                .help("Open Location System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct ApplePermissionAccessStatusLabel: View {
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

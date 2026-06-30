import EventKit
import SwiftUI

struct PermissionsSettingsView: View {
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var settingsStore: SettingsStore
    @Bindable var appStore: AppStore
    @State private var calendarReadAuthorized: Bool

    init(
        permissionsStore: PermissionsStore,
        settingsStore: SettingsStore,
        appStore: AppStore
    ) {
        self.permissionsStore = permissionsStore
        self.settingsStore = settingsStore
        self.appStore = appStore
        _calendarReadAuthorized = State(
            initialValue: EventsPermissionStatusMapper.map(
                EKEventStore.authorizationStatus(for: .event)
            ).grantsReadAccess
        )
    }

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
                AppleLocationPermissionRow(
                    required: permissionsStore.requiresAppleLocationAccess,
                    granted: appStore.locationPermissionStatus.grantsReadAccess,
                    isRequestingPermission: appStore.isRequestingLocationPermission,
                    onOpenSystemSettings: { appStore.openLocationPrivacySettings() },
                    onRequestPermissions: { Task { await appStore.requestLocationAccess() } }
                )
            } header: {
                Text("Apple Permissions")
            } footer: {
                Text(
                    "To view or revoke what macOS has granted, use System Settings. "
                        + "Vision tools analyze image data supplied by MCP clients; "
                        + "no macOS privacy permission is required for this foundation."
                )
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
                MapKitMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
                VisionMCPPermissionsGroup { capabilityID in
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
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                    locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
                )
            }
        }
        .onChange(of: appStore.calendarPermissionStatus.grantsReadAccess) { _, eventsAuthorized in
            guard eventsAuthorized, permissionsStore.requiresCalendarAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: true,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                    locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
                )
            }
        }
        .onChange(of: appStore.contactsPermissionStatus.grantsReadAccess) { _, contactsAuthorized in
            guard contactsAuthorized, permissionsStore.requiresAppleContactsAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: true,
                    locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
                )
            }
        }
        .onChange(of: appStore.locationPermissionStatus.grantsReadAccess) { _, locationAuthorized in
            guard locationAuthorized, permissionsStore.requiresAppleLocationAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                    locationAuthorized: true
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
                let authorization = ApplePermissionAuthorization(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                    locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
                )
                guard permissionsStore.shouldApplySavedCapabilitiesAfterToggle(
                    enabling: newValue,
                    capabilityID: capabilityID,
                    authorization: authorization
                ) else { return }
                let remindersAuthorized = authorization.remindersAuthorized
                let eventsAuthorized = authorization.eventsAuthorized
                let contactsAuthorized = authorization.contactsAuthorized
                let locationAuthorized = authorization.locationAuthorized
                Task {
                    await settingsStore.applySavedCapabilities(
                        remindersAuthorized: remindersAuthorized,
                        eventsAuthorized: eventsAuthorized,
                        contactsAuthorized: contactsAuthorized,
                        locationAuthorized: locationAuthorized
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
                contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
            )
        }
    }
}

import SwiftUI

struct PermissionsSettingsView: View {
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var settingsStore: SettingsStore
    @Bindable var appStore: AppStore
    let calendarSharingStore: CalendarSharingStore
    /// Previous OS grant flags for external System Settings reconciliation after refresh.
    @State private var previousOSGrants: OSAccessGrantSnapshot

    init(
        permissionsStore: PermissionsStore,
        settingsStore: SettingsStore,
        appStore: AppStore,
        calendarSharingStore: CalendarSharingStore
    ) {
        self.permissionsStore = permissionsStore
        self.settingsStore = settingsStore
        self.appStore = appStore
        self.calendarSharingStore = calendarSharingStore
        _previousOSGrants = State(initialValue: OSAccessGrantSnapshot(from: appStore))
    }

    var body: some View {
        Form {
            Section {
                Text(
                    "macOS access gates which tools can go live. Enable a provider for a full shipped default set, "
                        + "or customize tools for fine-grained MCP capabilities."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Button("Request all permissions") {
                    Task { await appStore.requestAllPendingAccess() }
                }
                .disabled(!appStore.hasPendingOSAccessRequest || appStore.isRequestingAnyOSAccess)
            }

            ForEach(ProviderPermissionKind.allCases) { kind in
                Section {
                    providerCard(for: kind)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onAppear {
            permissionsStore.reloadFromSettings()
            refreshStatusAndReapplyIfAccessGranted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatusAndReapplyIfAccessGranted()
        }
        .onChange(of: appStore.permissionStatus.grantsReadAccess) { _, remindersAuthorized in
            guard remindersAuthorized, permissionsStore.requiresAppleRemindersAccess else { return }
            previousOSGrants.reminders = true
            applyAfterMutation()
        }
        .onChange(of: appStore.calendarPermissionStatus.grantsReadAccess) { _, eventsAuthorized in
            guard eventsAuthorized, permissionsStore.requiresCalendarAccess else { return }
            previousOSGrants.events = true
            applyAfterMutation()
        }
        .onChange(of: appStore.contactsPermissionStatus.grantsReadAccess) { _, contactsAuthorized in
            guard contactsAuthorized, permissionsStore.requiresAppleContactsAccess else { return }
            previousOSGrants.contacts = true
            applyAfterMutation()
        }
        .onChange(of: appStore.locationPermissionStatus.grantsReadAccess) { _, locationAuthorized in
            guard locationAuthorized, permissionsStore.requiresAppleLocationAccess else { return }
            previousOSGrants.location = true
            applyAfterMutation()
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

    private func providerCard(for kind: ProviderPermissionKind) -> ProviderPermissionsCard {
        let os = osWiring(for: kind)
        return ProviderPermissionsCard(
            kind: kind,
            status: ProviderPermissionStatus.compute(
                checkedShippedCount: permissionsStore.checkedShippedCount(for: kind),
                needsOSAccess: kind.needsOSAccess,
                osGrantsReadAccess: os.grantsReadAccess,
                osIsDeniedOrRestricted: os.isDeniedOrRestricted
            ),
            checkedShippedCount: permissionsStore.checkedShippedCount(for: kind),
            enableState: permissionsStore.enableState(for: kind),
            osAccessTitle: os.title,
            osAccessStatusLabel: os.statusLabel,
            osGrantsReadAccess: os.grantsReadAccess,
            osIsDeniedOrRestricted: os.isDeniedOrRestricted,
            isRequesting: os.isRequesting,
            capabilityGroups: capabilityGroups(for: kind),
            capabilityBinding: binding(for:),
            onEnableChange: { setProviderEnabled($0, for: kind) },
            onEnableAll: { enableAll(for: kind) },
            onDisableAll: { disableAll(for: kind) },
            onRequestAccess: os.onRequest,
            onOpenSystemSettings: os.onOpenSettings,
            calendarSharingStore: calendarSharingStore
        )
    }

    private func capabilityGroups(
        for kind: ProviderPermissionKind
    ) -> [(header: String?, items: [CapabilityDefinition])] {
        switch kind {
        case .reminders:
            [(header: nil, items: CapabilityCatalog.remindersCapabilities.filter(\.shipped))]
        case .calendarsAndEvents:
            [
                (header: "Calendars", items: CapabilityCatalog.calendarsCapabilities.filter(\.shipped)),
                (header: "Events", items: CapabilityCatalog.eventsCapabilities.filter(\.shipped)),
            ]
        case .contacts:
            [(header: nil, items: CapabilityCatalog.contactsCapabilities.filter(\.shipped))]
        case .mapkit:
            [(header: nil, items: CapabilityCatalog.mapkitCapabilities.filter(\.shipped))]
        case .vision:
            [(header: nil, items: CapabilityCatalog.visionCapabilities.filter(\.shipped))]
        }
    }

    private func osWiring(for kind: ProviderPermissionKind) -> ProviderOSWiring {
        switch kind {
        case .reminders: remindersOSWiring
        case .calendarsAndEvents: calendarsOSWiring
        case .contacts: contactsOSWiring
        case .mapkit: mapkitOSWiring
        case .vision: visionOSWiring
        }
    }

    private var remindersOSWiring: ProviderOSWiring {
        let granted = appStore.permissionStatus.grantsReadAccess
        return ProviderOSWiring(
            title: "Reminders Full Access",
            statusLabel: osAccessLabel(granted: granted, displayName: appStore.permissionStatus.displayName),
            grantsReadAccess: granted,
            isDeniedOrRestricted: isDeniedOrRestricted(appStore.permissionStatus),
            isRequesting: appStore.isRequestingPermission,
            onRequest: { Task { await appStore.requestAccess() } },
            onOpenSettings: { appStore.openRemindersPrivacySettings() }
        )
    }

    private var calendarsOSWiring: ProviderOSWiring {
        let granted = appStore.calendarPermissionStatus.grantsReadAccess
        return ProviderOSWiring(
            title: "Calendars Full Access",
            statusLabel: osAccessLabel(granted: granted, displayName: appStore.calendarPermissionStatus.displayName),
            grantsReadAccess: granted,
            isDeniedOrRestricted: isDeniedOrRestricted(appStore.calendarPermissionStatus),
            isRequesting: appStore.isRequestingCalendarPermission,
            onRequest: { Task { await appStore.requestCalendarAccess() } },
            onOpenSettings: { appStore.openCalendarPrivacySettings() }
        )
    }

    private var contactsOSWiring: ProviderOSWiring {
        let granted = appStore.contactsPermissionStatus.grantsReadAccess
        return ProviderOSWiring(
            title: "Contacts Access",
            statusLabel: osAccessLabel(granted: granted, displayName: appStore.contactsPermissionStatus.displayName),
            grantsReadAccess: granted,
            isDeniedOrRestricted: isDeniedOrRestricted(appStore.contactsPermissionStatus),
            isRequesting: appStore.isRequestingContactsPermission,
            onRequest: { Task { await appStore.requestContactsAccess() } },
            onOpenSettings: { appStore.openContactsPrivacySettings() }
        )
    }

    private var mapkitOSWiring: ProviderOSWiring {
        let granted = appStore.locationPermissionStatus.grantsReadAccess
        return ProviderOSWiring(
            title: "Location Access",
            statusLabel: osAccessLabel(granted: granted, displayName: appStore.locationPermissionStatus.displayName),
            grantsReadAccess: granted,
            isDeniedOrRestricted: isDeniedOrRestricted(appStore.locationPermissionStatus),
            isRequesting: appStore.isRequestingLocationPermission,
            onRequest: { Task { await appStore.requestLocationAccess() } },
            onOpenSettings: { appStore.openLocationPrivacySettings() }
        )
    }

    private var visionOSWiring: ProviderOSWiring {
        ProviderOSWiring(
            title: nil,
            statusLabel: "Analyzes image data from MCP clients — no macOS privacy permission required.",
            grantsReadAccess: true,
            isDeniedOrRestricted: false,
            isRequesting: false,
            onRequest: {},
            onOpenSettings: {}
        )
    }

    private func osAccessLabel(granted: Bool, displayName: String) -> String {
        granted ? "Granted" : displayName
    }

    private func isDeniedOrRestricted(_ status: RemindersPermissionStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private func isDeniedOrRestricted(_ status: EventsPermissionStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private func isDeniedOrRestricted(_ status: ContactsPermissionStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private func isDeniedOrRestricted(_ status: LocationPermissionStatus) -> Bool {
        status == .denied || status == .restricted
    }

    private func setProviderEnabled(_ enabled: Bool, for kind: ProviderPermissionKind) {
        permissionsStore.setProviderEnabled(enabled, for: kind)
        applyAfterMutation()
    }

    private func enableAll(for kind: ProviderPermissionKind) {
        permissionsStore.enableAllShipped(for: kind)
        applyAfterMutation()
    }

    private func disableAll(for kind: ProviderPermissionKind) {
        permissionsStore.disableAllShipped(for: kind)
        applyAfterMutation()
    }

    private func binding(for capabilityID: String) -> Binding<Bool> {
        Binding(
            get: { permissionsStore.checkedCapabilityIDs.contains(capabilityID) },
            set: { newValue in
                permissionsStore.setChecked(newValue, for: capabilityID)
                applyAfterMutation()
            }
        )
    }

    private func applyAfterMutation() {
        Task {
            await settingsStore.applySavedCapabilities(
                remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                locationAuthorized: appStore.locationPermissionStatus.grantsReadAccess
            )
        }
    }

    /// Refresh TCC status, then apply saved MCP caps when any required OS access newly became granted
    /// (e.g. user returned from System Settings). Covers cases where SwiftUI `.onChange` may not fire.
    private func refreshStatusAndReapplyIfAccessGranted() {
        appStore.refreshStatus()
        let current = OSAccessGrantSnapshot(from: appStore)
        let becameAuthorized =
            (!previousOSGrants.reminders && current.reminders && permissionsStore.requiresAppleRemindersAccess)
                || (!previousOSGrants.events && current.events && permissionsStore.requiresCalendarAccess)
                || (!previousOSGrants.contacts && current.contacts && permissionsStore.requiresAppleContactsAccess)
                || (!previousOSGrants.location && current.location && permissionsStore.requiresAppleLocationAccess)
        previousOSGrants = current
        guard becameAuthorized else { return }
        applyAfterMutation()
    }
}

@MainActor
private struct OSAccessGrantSnapshot: Equatable {
    var reminders: Bool
    var events: Bool
    var contacts: Bool
    var location: Bool

    init(from appStore: AppStore) {
        reminders = appStore.permissionStatus.grantsReadAccess
        events = appStore.calendarPermissionStatus.grantsReadAccess
        contacts = appStore.contactsPermissionStatus.grantsReadAccess
        location = appStore.locationPermissionStatus.grantsReadAccess
    }
}

private struct ProviderOSWiring {
    let title: String?
    let statusLabel: String
    let grantsReadAccess: Bool
    let isDeniedOrRestricted: Bool
    let isRequesting: Bool
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
}

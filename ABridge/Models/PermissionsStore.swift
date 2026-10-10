import Foundation
import Observation

@Observable
@MainActor
final class PermissionsStore {
    private(set) var checkedCapabilityIDs: Set<String>

    private let appSettings: AppSettings

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        checkedCapabilityIDs = appSettings.savedCapabilityIDs
    }

    var savedCapabilityIDs: Set<String> {
        appSettings.savedCapabilityIDs
    }

    var requiresAppleRemindersAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.remindersCapabilities.contains { $0.id == id && $0.shipped }
        }
    }

    var requiresAppleContactsAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.contactsCapabilities.contains { $0.id == id && $0.shipped }
        }
    }

    var requiresAppleLocationAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.corelocationCapabilities.contains { $0.id == id && $0.shipped }
        }
    }

    func setChecked(_ checked: Bool, for capabilityID: String) {
        if checked {
            checkedCapabilityIDs.insert(capabilityID)
        } else {
            checkedCapabilityIDs.remove(capabilityID)
        }
        persistCapabilities()
    }

    func persistCapabilities() {
        appSettings.saveCapabilityIDs(checkedCapabilityIDs)
    }

    func reloadFromSettings() {
        checkedCapabilityIDs = appSettings.savedCapabilityIDs
    }

    func shouldApplySavedCapabilitiesAfterToggle(
        enabling: Bool,
        capabilityID: String,
        authorization: ApplePermissionAuthorization
    ) -> Bool {
        guard enabling else { return true }

        if CapabilityCatalog.calendarsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return authorization.eventsAuthorized
        }

        if CapabilityCatalog.eventsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return authorization.eventsAuthorized
        }

        if CapabilityCatalog.contactsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return authorization.contactsAuthorized
        }

        if CapabilityCatalog.mapkitCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return true
        }

        if CapabilityCatalog.corelocationCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return authorization.locationAuthorized
        }

        if CapabilityCatalog.visionCapabilities.contains(where: { $0.id == capabilityID }) {
            return true
        }

        return authorization.remindersAuthorized
    }

    var requiresCalendarAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.calendarsCapabilities.contains { $0.id == id && $0.shipped }
                || CapabilityCatalog.eventsCapabilities.contains { $0.id == id && $0.shipped }
        }
    }

    func shippedCapabilityIDs(for kind: ProviderPermissionKind) -> [String] {
        switch kind {
        case .reminders:
            CapabilityCatalog.remindersCapabilities.filter(\.shipped).map(\.id)
        case .calendarsAndEvents:
            (
                CapabilityCatalog.calendarsCapabilities
                    + CapabilityCatalog.eventsCapabilities
            )
            .filter(\.shipped)
            .map(\.id)
        case .contacts:
            CapabilityCatalog.contactsCapabilities.filter(\.shipped).map(\.id)
        case .mapkit:
            CapabilityCatalog.mapkitCapabilities.filter(\.shipped).map(\.id)
        case .corelocation:
            CapabilityCatalog.corelocationCapabilities.filter(\.shipped).map(\.id)
        case .vision:
            CapabilityCatalog.visionCapabilities.filter(\.shipped).map(\.id)
        }
    }

    func checkedShippedCount(for kind: ProviderPermissionKind) -> Int {
        shippedCapabilityIDs(for: kind).count(where: { checkedCapabilityIDs.contains($0) })
    }

    func enableState(for kind: ProviderPermissionKind) -> ProviderEnableState {
        let ids = shippedCapabilityIDs(for: kind)
        return .compute(checked: checkedShippedCount(for: kind), totalShipped: ids.count)
    }

    func enableAllShipped(for kind: ProviderPermissionKind) {
        for id in shippedCapabilityIDs(for: kind) {
            checkedCapabilityIDs.insert(id)
        }
        persistCapabilities()
    }

    func disableAllShipped(for kind: ProviderPermissionKind) {
        for id in shippedCapabilityIDs(for: kind) {
            checkedCapabilityIDs.remove(id)
        }
        persistCapabilities()
    }

    func setProviderEnabled(_ enabled: Bool, for kind: ProviderPermissionKind) {
        if enabled {
            enableAllShipped(for: kind)
        } else {
            disableAllShipped(for: kind)
        }
    }
}

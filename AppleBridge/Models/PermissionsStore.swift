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
            CapabilityCatalog.mapkitCapabilities.contains { $0.id == id && $0.shipped }
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
            return authorization.locationAuthorized
        }

        return authorization.remindersAuthorized
    }

    var requiresCalendarAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.calendarsCapabilities.contains { $0.id == id && $0.shipped }
                || CapabilityCatalog.eventsCapabilities.contains { $0.id == id && $0.shipped }
        }
    }
}

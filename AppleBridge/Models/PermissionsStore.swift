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

    func shouldApplySavedCapabilitiesAfterToggle(enabling: Bool, remindersAuthorized: Bool) -> Bool {
        remindersAuthorized || !enabling
    }
}

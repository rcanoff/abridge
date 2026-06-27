import Foundation
import Observation

enum AppleEnforcementTag: Equatable, Sendable {
    case notApplicable
    case needed
    case granted

    var label: String {
        switch self {
        case .notApplicable:
            return "Apple —"
        case .needed:
            return "Apple needed"
        case .granted:
            return "Apple granted"
        }
    }
}

enum MCPEnforcementTag: Equatable, Sendable {
    case active
    case pending
    case off
    case blocked

    var label: String {
        switch self {
        case .active:
            return "MCP active"
        case .pending:
            return "MCP pending"
        case .off:
            return "MCP off"
        case .blocked:
            return "MCP blocked"
        }
    }
}

struct CapabilityEnforcement: Equatable, Sendable {
    let apple: AppleEnforcementTag
    let mcp: MCPEnforcementTag
}

enum PermissionsDerivation {
    static func computeEnforcement(
        for capability: CapabilityDefinition,
        checked: Bool,
        saved: Bool,
        remindersAuthorized: Bool
    ) -> CapabilityEnforcement {
        if !capability.shipped {
            let apple: AppleEnforcementTag
            if !checked {
                apple = .notApplicable
            } else if remindersAuthorized {
                apple = .granted
            } else {
                apple = .needed
            }
            return CapabilityEnforcement(apple: apple, mcp: .blocked)
        }

        let mcp: MCPEnforcementTag
        if saved && checked {
            mcp = .active
        } else if checked {
            mcp = .pending
        } else {
            mcp = .off
        }

        let apple: AppleEnforcementTag
        if !checked && !saved {
            apple = .notApplicable
        } else if remindersAuthorized {
            apple = .granted
        } else {
            apple = .needed
        }

        return CapabilityEnforcement(apple: apple, mcp: mcp)
    }

    static func mcpSummary(
        savedCapabilityIDs: Set<String>,
        checkedCapabilityIDs: Set<String>
    ) -> String {
        let active = CapabilityCatalog.remindersCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.label)

        if !active.isEmpty {
            return active.joined(separator: ", ") + " active"
        }

        let blocked = CapabilityCatalog.remindersCapabilities
            .filter { !$0.shipped && checkedCapabilityIDs.contains($0.id) }
            .map(\.label)

        if !blocked.isEmpty {
            return "Blocked: " + blocked.joined(separator: ", ")
        }

        return "None active"
    }

    static func appleSummary(
        checkedCapabilityIDs: Set<String>,
        remindersAuthorized: Bool
    ) -> String {
        if checkedCapabilityIDs.isEmpty {
            return "None"
        }

        if remindersAuthorized {
            return "Reminders — Full access"
        }

        return "Reminders — needed"
    }

    static func hasPendingChanges(
        checkedCapabilityIDs: Set<String>,
        savedCapabilityIDs: Set<String>
    ) -> Bool {
        for capability in CapabilityCatalog.remindersCapabilities where capability.shipped {
            let checked = checkedCapabilityIDs.contains(capability.id)
            let saved = savedCapabilityIDs.contains(capability.id)
            if checked != saved {
                return true
            }
        }

        return false
    }

    static func requiresAppleAccess(for checkedCapabilityIDs: Set<String>) -> Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.remindersCapabilities.contains { $0.id == id && $0.shipped }
        }
    }

    static func savedIDsAfterSave(from checkedCapabilityIDs: Set<String>) -> Set<String> {
        Set(
            checkedCapabilityIDs.filter { id in
                CapabilityCatalog.remindersCapabilities.contains { $0.id == id && $0.shipped }
            }
        )
    }
}

@Observable
@MainActor
final class PermissionsStore {
    private(set) var checkedCapabilityIDs: Set<String>
    private(set) var lastError: String?

    private let appSettings: AppSettings
    private let permissionService: any RemindersPermissionChecking

    init(
        appSettings: AppSettings,
        permissionService: any RemindersPermissionChecking = RemindersPermissionService()
    ) {
        self.appSettings = appSettings
        self.permissionService = permissionService
        checkedCapabilityIDs = appSettings.savedCapabilityIDs
    }

    var savedCapabilityIDs: Set<String> {
        appSettings.savedCapabilityIDs
    }

    var remindersAuthorized: Bool {
        permissionService.currentStatus() == .authorized
    }

    func enforcement(for capability: CapabilityDefinition) -> CapabilityEnforcement {
        PermissionsDerivation.computeEnforcement(
            for: capability,
            checked: checkedCapabilityIDs.contains(capability.id),
            saved: savedCapabilityIDs.contains(capability.id),
            remindersAuthorized: remindersAuthorized
        )
    }

    var mcpSummaryLine: String {
        PermissionsDerivation.mcpSummary(
            savedCapabilityIDs: savedCapabilityIDs,
            checkedCapabilityIDs: checkedCapabilityIDs
        )
    }

    var appleSummaryLine: String {
        PermissionsDerivation.appleSummary(
            checkedCapabilityIDs: checkedCapabilityIDs,
            remindersAuthorized: remindersAuthorized
        )
    }

    var hasPendingChanges: Bool {
        PermissionsDerivation.hasPendingChanges(
            checkedCapabilityIDs: checkedCapabilityIDs,
            savedCapabilityIDs: savedCapabilityIDs
        )
    }

    func setChecked(_ checked: Bool, for capabilityID: String) {
        if checked {
            checkedCapabilityIDs.insert(capabilityID)
        } else {
            checkedCapabilityIDs.remove(capabilityID)
        }
    }

    func save() async -> Bool {
        lastError = nil

        if needsAppleAccess(), !remindersAuthorized {
            do {
                let status = try await permissionService.requestAccess()
                guard status == .authorized else {
                    lastError = "Reminders access was not granted."
                    return false
                }
            } catch {
                lastError = error.localizedDescription
                return false
            }
        }

        let persisted = PermissionsDerivation.savedIDsAfterSave(from: checkedCapabilityIDs)
        appSettings.saveCapabilityIDs(persisted)
        return true
    }

    func reloadFromSettings() {
        checkedCapabilityIDs = appSettings.savedCapabilityIDs
    }

    private func needsAppleAccess() -> Bool {
        PermissionsDerivation.requiresAppleAccess(for: checkedCapabilityIDs)
    }
}
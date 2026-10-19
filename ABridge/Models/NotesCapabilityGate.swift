import Foundation

struct NotesCapabilityAccess: Equatable {
    var sendsAll: Bool
    var blocksWrites: Bool
}

/// Which Notes capability IDs the server may receive for a Full Disk Access and Automation pair.
enum NotesCapabilityGate {
    static let readCapabilityIDs: Set<String> = ["notes.read", "notes.search"]
    static let writeCapabilityIDs: Set<String> = ["notes.create", "notes.edit", "notes.delete"]

    static func isWrite(_ capabilityID: String) -> Bool {
        writeCapabilityIDs.contains(capabilityID)
    }

    static func shouldSend(
        capabilityID: String,
        fullDiskAccessGranted: Bool,
        automationDenied: Bool
    ) -> Bool {
        guard fullDiskAccessGranted else { return false }
        if readCapabilityIDs.contains(capabilityID) {
            return true
        }
        if writeCapabilityIDs.contains(capabilityID) {
            return !automationDenied
        }
        return false
    }

    static func serverCapabilityIDs(
        enabled: [String],
        fullDiskAccessGranted: Bool,
        automationDenied: Bool
    ) -> [String] {
        enabled.filter { capabilityID in
            shouldSend(
                capabilityID: capabilityID,
                fullDiskAccessGranted: fullDiskAccessGranted,
                automationDenied: automationDenied
            )
        }
    }

    static func access(
        for capabilityIDs: [String],
        fullDiskAccessGranted: Bool,
        automationDenied: Bool
    ) -> NotesCapabilityAccess {
        let sendsAll = capabilityIDs.allSatisfy { capabilityID in
            shouldSend(
                capabilityID: capabilityID,
                fullDiskAccessGranted: fullDiskAccessGranted,
                automationDenied: automationDenied
            )
        }
        let blocksWrites = capabilityIDs.contains { capabilityID in
            isWrite(capabilityID) && fullDiskAccessGranted && automationDenied
        }
        return NotesCapabilityAccess(sendsAll: sendsAll, blocksWrites: blocksWrites)
    }
}

/// Full Disk Access and Automation as they affect which Notes capabilities the server may receive.
struct NotesAccessGrant: Equatable {
    var fullDiskAccessGranted: Bool
    var automationAllowsWrite: Bool
}

/// When a Notes OS-grant change must be pushed to the running server.
enum NotesAccessGrantReconciliation {
    /// True when the effective Notes grant changed in either direction and saved caps must be re-sent.
    /// Other providers stay gain-only; this decision is Notes-only.
    static func shouldReapply(
        previous: NotesAccessGrant,
        current: NotesAccessGrant,
        requiresNotesAccess: Bool,
        requiresNotesWriteAccess: Bool
    ) -> Bool {
        if previous.fullDiskAccessGranted != current.fullDiskAccessGranted, requiresNotesAccess {
            return true
        }
        let automationWriteChanged = previous.automationAllowsWrite != current.automationAllowsWrite
        return automationWriteChanged && current.fullDiskAccessGranted && requiresNotesWriteAccess
    }
}

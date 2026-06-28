import Foundation

struct CapabilityDefinition: Identifiable, Equatable {
    let id: String
    let capabilityID: String
    let label: String
    let shipped: Bool
}

enum CapabilityCatalog {
    static let remindersCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(id: "read", capabilityID: "eventkit.reminders.read", label: "Read", shipped: true),
        CapabilityDefinition(id: "create", capabilityID: "eventkit.reminders.create", label: "Create", shipped: true),
        CapabilityDefinition(id: "edit", capabilityID: "eventkit.reminders.edit", label: "Edit", shipped: true),
        CapabilityDefinition(id: "delete", capabilityID: "eventkit.reminders.delete", label: "Delete", shipped: false),
        CapabilityDefinition(
            id: "complete",
            capabilityID: "eventkit.reminders.complete",
            label: "Complete",
            shipped: true
        ),
        CapabilityDefinition(id: "alarms", capabilityID: "eventkit.reminders.alarms", label: "Alarms", shipped: true),
        CapabilityDefinition(
            id: "recurrence",
            capabilityID: "eventkit.reminders.recurrence",
            label: "Recurrence",
            shipped: true
        ),
        CapabilityDefinition(id: "search", capabilityID: "eventkit.reminders.search", label: "Search", shipped: true),
    ]
}

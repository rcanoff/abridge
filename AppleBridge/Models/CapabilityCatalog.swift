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
        CapabilityDefinition(id: "delete", capabilityID: "eventkit.reminders.delete", label: "Delete", shipped: true),
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

    static let calendarsCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(
            id: "calendars-read",
            capabilityID: "eventkit.calendars.read",
            label: "Read",
            shipped: true
        ),
        CapabilityDefinition(
            id: "calendars-create",
            capabilityID: "eventkit.calendars.create",
            label: "Create",
            shipped: true
        ),
        CapabilityDefinition(
            id: "calendars-edit",
            capabilityID: "eventkit.calendars.edit",
            label: "Edit",
            shipped: true
        ),
        CapabilityDefinition(
            id: "calendars-delete",
            capabilityID: "eventkit.calendars.delete",
            label: "Delete",
            shipped: true
        ),
    ]

    static let eventsCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(
            id: "events-read",
            capabilityID: "eventkit.events.read",
            label: "Read",
            shipped: true
        ),
        CapabilityDefinition(
            id: "events-search",
            capabilityID: "eventkit.events.search",
            label: "Search",
            shipped: true
        ),
        CapabilityDefinition(
            id: "events-create",
            capabilityID: "eventkit.events.create",
            label: "Create",
            shipped: true
        ),
        CapabilityDefinition(
            id: "events-edit",
            capabilityID: "eventkit.events.edit",
            label: "Edit",
            shipped: true
        ),
        CapabilityDefinition(
            id: "events-delete",
            capabilityID: "eventkit.events.delete",
            label: "Delete",
            shipped: true
        ),
        CapabilityDefinition(
            id: "events-alarms",
            capabilityID: "eventkit.events.alarms",
            label: "Alarms",
            shipped: true
        ),
    ]
}

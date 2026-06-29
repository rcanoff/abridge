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
        CapabilityDefinition(
            id: "events-recurrence",
            capabilityID: "eventkit.events.recurrence",
            label: "Recurrence",
            shipped: true
        ),
        // accept_invitation, decline_invitation, and tentative_invitation register in
        // Rust when the capability is enabled in MCP config. Settings hides this until a
        // live macOS EventKit RSVP API exists. LiveEventKitStore returns an explicit
        // eventKitError; mock store mutates attendee status for CI/tests (#70 AC2).
        CapabilityDefinition(
            id: "events-invitations",
            capabilityID: "eventkit.events.invitations",
            label: "Invitations",
            shipped: false
        ),
    ]

    static let contactsCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(id: "contacts-read", capabilityID: "contacts.read", label: "Read", shipped: true),
        CapabilityDefinition(id: "contacts-search", capabilityID: "contacts.search", label: "Search", shipped: true),
        CapabilityDefinition(id: "contacts-create", capabilityID: "contacts.create", label: "Create", shipped: true),
        CapabilityDefinition(id: "contacts-edit", capabilityID: "contacts.edit", label: "Edit", shipped: true),
        CapabilityDefinition(id: "contacts-delete", capabilityID: "contacts.delete", label: "Delete", shipped: true),
    ]

    static let mapkitCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(id: "mapkit-search", capabilityID: "mapkit.search", label: "Search", shipped: true),
        CapabilityDefinition(id: "mapkit-geocode", capabilityID: "mapkit.geocode", label: "Geocode", shipped: true),
        CapabilityDefinition(id: "mapkit-routing", capabilityID: "mapkit.routing", label: "Routing", shipped: true),
        CapabilityDefinition(
            id: "mapkit-navigation",
            capabilityID: "mapkit.navigation",
            label: "Navigation",
            shipped: true
        ),
        CapabilityDefinition(id: "mapkit-location", capabilityID: "mapkit.location", label: "Location", shipped: false),
        CapabilityDefinition(id: "mapkit-read", capabilityID: "mapkit.read", label: "Read", shipped: true),
    ]
}

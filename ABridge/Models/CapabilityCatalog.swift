import Foundation

struct CapabilityDefinition: Identifiable, Equatable {
    let id: String
    let capabilityID: String
    let label: String
    let shipped: Bool

    init(id: String, capabilityID: String, label: String, shipped: Bool) {
        self.id = id
        self.capabilityID = capabilityID
        self.label = label
        self.shipped = shipped
    }

    /// Map from the Rust-owned UniFFI catalog entry (single source of truth).
    init(_ entry: SettingsCapabilityDefinition) {
        id = entry.id
        capabilityID = entry.capabilityId
        label = entry.label
        shipped = entry.shipped
    }
}

/// Settings capability groups. IDs and labels come from Rust `list_settings_capabilities()`.
enum CapabilityCatalog {
    private static let all: [SettingsCapabilityDefinition] = listSettingsCapabilities()

    private static func definitions(in group: String) -> [CapabilityDefinition] {
        all.filter { $0.group == group }.map(CapabilityDefinition.init)
    }

    static var remindersCapabilities: [CapabilityDefinition] {
        definitions(in: "reminders")
    }

    static var calendarsCapabilities: [CapabilityDefinition] {
        definitions(in: "calendars")
    }

    static var eventsCapabilities: [CapabilityDefinition] {
        definitions(in: "events")
    }

    static var contactsCapabilities: [CapabilityDefinition] {
        definitions(in: "contacts")
    }

    static var mapkitCapabilities: [CapabilityDefinition] {
        definitions(in: "mapkit")
    }

    static var corelocationCapabilities: [CapabilityDefinition] {
        definitions(in: "corelocation")
    }

    static var visionCapabilities: [CapabilityDefinition] {
        definitions(in: "vision")
    }
}

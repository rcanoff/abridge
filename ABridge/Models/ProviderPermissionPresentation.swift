import Foundation

enum ProviderPermissionKind: String, CaseIterable, Identifiable {
    case reminders
    case calendarsAndEvents
    case contacts
    case mapkit
    case vision

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .reminders: "Reminders"
        case .calendarsAndEvents: "Calendars & Events"
        case .contacts: "Contacts"
        case .mapkit: "MapKit"
        case .vision: "Vision"
        }
    }

    var needsOSAccess: Bool {
        self != .vision
    }

    /// Calendar collection whose MCP sharing the user can narrow, if any.
    var calendarSharingKind: CalendarSharingKind? {
        switch self {
        case .reminders: .reminderLists
        case .calendarsAndEvents: .eventCalendars
        case .contacts, .mapkit, .vision: nil
        }
    }
}

enum ProviderPermissionStatus: Equatable {
    case notInUse
    case needsAccess
    case blocked
    case ready

    static func compute(
        checkedShippedCount: Int,
        needsOSAccess: Bool,
        osGrantsReadAccess: Bool,
        osIsDeniedOrRestricted: Bool
    ) -> ProviderPermissionStatus {
        guard checkedShippedCount > 0 else { return .notInUse }
        guard needsOSAccess else { return .ready }
        if osGrantsReadAccess { return .ready }
        if osIsDeniedOrRestricted { return .blocked }
        return .needsAccess
    }

    var label: String {
        switch self {
        case .notInUse: "Not in use"
        case .needsAccess: "Needs access"
        case .blocked: "Blocked"
        case .ready: "Ready"
        }
    }
}

enum ProviderEnableState: Equatable {
    case off
    case on
    case mixed

    static func compute(checked: Int, totalShipped: Int) -> ProviderEnableState {
        guard totalShipped > 0 else { return .off }
        if checked <= 0 { return .off }
        if checked >= totalShipped { return .on }
        return .mixed
    }
}

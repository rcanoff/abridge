import Foundation

/// EventKit calendar collection whose MCP visibility the user can narrow.
enum CalendarSharingKind: String, CaseIterable, Sendable {
    case reminderLists
    case eventCalendars
}

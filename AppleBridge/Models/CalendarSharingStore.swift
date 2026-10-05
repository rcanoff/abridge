@preconcurrency import EventKit
import Foundation
import Observation

/// Which EventKit calendars MCP tools may access. A kind without a saved selection shares every
/// calendar (the default); a saved selection limits access to those calendar identifiers.
@Observable
@MainActor
final class CalendarSharingStore {
    private(set) var sharedIdentifiersByKind: [CalendarSharingKind: Set<String>]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loadCalendars: @MainActor (CalendarSharingKind) -> [EKCalendar]

    init(
        defaults: UserDefaults = .standard,
        loadCalendars: @escaping @MainActor (CalendarSharingKind) -> [EKCalendar]
    ) {
        self.defaults = defaults
        self.loadCalendars = loadCalendars
        var stored: [CalendarSharingKind: Set<String>] = [:]
        for kind in CalendarSharingKind.allCases {
            if let identifiers = defaults.stringArray(forKey: Self.defaultsKey(for: kind)) {
                stored[kind] = Set(identifiers)
            }
        }
        sharedIdentifiersByKind = stored
    }

    /// `nil` when every calendar of `kind` is shared.
    func sharedIdentifiers(for kind: CalendarSharingKind) -> Set<String>? {
        sharedIdentifiersByKind[kind]
    }

    /// Pass `nil` to share every calendar of `kind`.
    func setSharedIdentifiers(_ identifiers: Set<String>?, for kind: CalendarSharingKind) {
        sharedIdentifiersByKind[kind] = identifiers
        let key = Self.defaultsKey(for: kind)
        if let identifiers {
            defaults.set(identifiers.sorted(), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func isShared(_ calendar: EKCalendar?, for kind: CalendarSharingKind) -> Bool {
        guard let identifiers = sharedIdentifiersByKind[kind] else { return true }
        guard let calendar else { return false }
        return identifiers.contains(calendar.calendarIdentifier)
    }

    /// Calendars created through MCP join a custom selection so the client can keep using them.
    func shareCreatedCalendar(identifier: String, for kind: CalendarSharingKind) {
        guard var identifiers = sharedIdentifiersByKind[kind], !identifiers.contains(identifier) else { return }
        identifiers.insert(identifier)
        setSharedIdentifiers(identifiers, for: kind)
    }

    /// Every calendar of `kind` on this Mac, shared or not.
    func availableCalendars(for kind: CalendarSharingKind) -> [EKCalendar] {
        loadCalendars(kind)
    }

    private static func defaultsKey(for kind: CalendarSharingKind) -> String {
        "sharedCalendarIdentifiers.\(kind.rawValue)"
    }
}

import SwiftUI

/// Opens the picker that limits which calendars or reminder lists MCP tools can access.
struct CalendarSharingButton: View {
    let kind: CalendarSharingKind
    let osGrantsReadAccess: Bool
    let calendarSharingStore: CalendarSharingStore

    @State private var isPresented = false

    var body: some View {
        Button(kind.sharingTitle, systemImage: symbolName) {
            isPresented = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(!osGrantsReadAccess)
        .help(helpText)
        .accessibilityValue(isSharingAll ? "All \(kind.pluralNoun)" : "Selected \(kind.pluralNoun)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            CalendarSharingPicker(kind: kind, calendarSharingStore: calendarSharingStore)
        }
    }

    private var isSharingAll: Bool {
        calendarSharingStore.sharedIdentifiers(for: kind) == nil
    }

    private var symbolName: String {
        isSharingAll ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    private var helpText: String {
        guard osGrantsReadAccess else {
            return "Grant access to choose which \(kind.pluralNoun) MCP can use"
        }
        return isSharingAll
            ? "MCP can use all \(kind.pluralNoun)"
            : "MCP can use selected \(kind.pluralNoun) only"
    }
}

extension CalendarSharingKind {
    var sharingTitle: String {
        switch self {
        case .reminderLists: "Shared Lists"
        case .eventCalendars: "Shared Calendars"
        }
    }

    var pluralNoun: String {
        switch self {
        case .reminderLists: "lists"
        case .eventCalendars: "calendars"
        }
    }
}

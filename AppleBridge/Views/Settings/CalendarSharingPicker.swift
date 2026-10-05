@preconcurrency import EventKit
import SwiftUI

/// Popover content: share every calendar of a kind (default) or only the checked ones.
struct CalendarSharingPicker: View {
    let kind: CalendarSharingKind
    let calendarSharingStore: CalendarSharingStore

    @State private var groups: [(source: String, calendars: [EKCalendar])] = []
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.sharingTitle)
                .font(.headline)

            Picker(kind.sharingTitle, selection: sharesAllBinding) {
                Text("All \(kind.pluralNoun)").tag(true)
                Text("Only selected \(kind.pluralNoun)").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            if groups.isEmpty {
                Text("No \(kind.pluralNoun) found.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    calendarList
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Popovers size to content; cap long account lists and scroll the rest.
                .frame(height: min(listHeight, 240))
                .disabled(sharesAll)
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 300)
        .onAppear(perform: loadCalendars)
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groups, id: \.source) { group in
                if !group.source.isEmpty {
                    Text(group.source)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                }

                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: sharedBinding(for: calendar)) {
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Circle()
                                .fill(calendar.cgColor.map { Color(cgColor: $0) } ?? .secondary)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sharesAll: Bool {
        calendarSharingStore.sharedIdentifiers(for: kind) == nil
    }

    private var footnote: String {
        if sharesAll {
            return "MCP can use every \(kind.singularNoun), including ones you add later."
        }
        return "New \(kind.pluralNoun) stay private until you check them. "
            + "\(kind.pluralNoun.capitalized) created through MCP are shared automatically."
    }

    private var sharesAllBinding: Binding<Bool> {
        Binding(
            get: { sharesAll },
            set: { sharesAll in
                guard sharesAll != self.sharesAll else { return }
                // Switching to a custom selection starts from everything shared, so access only
                // narrows as the user unchecks items.
                let identifiers = groups.flatMap(\.calendars).map(\.calendarIdentifier)
                calendarSharingStore.setSharedIdentifiers(sharesAll ? nil : Set(identifiers), for: kind)
            }
        )
    }

    private func sharedBinding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { calendarSharingStore.isShared(calendar, for: kind) },
            set: { isShared in
                guard var identifiers = calendarSharingStore.sharedIdentifiers(for: kind) else { return }
                if isShared {
                    identifiers.insert(calendar.calendarIdentifier)
                } else {
                    identifiers.remove(calendar.calendarIdentifier)
                }
                calendarSharingStore.setSharedIdentifiers(identifiers, for: kind)
            }
        )
    }

    private func loadCalendars() {
        let calendars = calendarSharingStore.availableCalendars(for: kind).sorted(by: Self.titleOrder)
        let bySource = Dictionary(grouping: calendars) { (calendar: EKCalendar) in calendar.source?.title ?? "" }
        let sources = bySource.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        groups = sources.map { source in (source: source, calendars: bySource[source] ?? []) }
    }

    private static func titleOrder(_ lhs: EKCalendar, _ rhs: EKCalendar) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private extension CalendarSharingKind {
    var singularNoun: String {
        switch self {
        case .reminderLists: "list"
        case .eventCalendars: "calendar"
        }
    }
}

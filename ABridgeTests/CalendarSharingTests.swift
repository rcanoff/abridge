@testable import ABridge
import Foundation
import Testing

@Suite("CalendarSharing")
@MainActor
struct CalendarSharingTests {
    private let defaults: UserDefaults
    private let mockStore = MockEventKitStore()
    private let sharing: CalendarSharingStore
    private let provider: EventKitProvider

    init() {
        let suiteName = "CalendarSharingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        sharing = CalendarSharingStore(defaults: defaults) { _ in [] }
        provider = EventKitProvider(store: SharedCalendarsEventKitStore(base: mockStore, sharing: sharing))

        mockStore.calendars = [
            mockStore.makeTestCalendar(calendarIdentifier: "list-home", title: "Home"),
            mockStore.makeTestCalendar(calendarIdentifier: "list-work", title: "Work"),
        ]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-home", calendarIdentifier: "list-home"),
            EventKitTestSupport.makeReminder(calendarItemIdentifier: "rem-work", calendarIdentifier: "list-work"),
        ]
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-home", title: "Home"),
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(calendarItemIdentifier: "evt-home", calendarIdentifier: "cal-home"),
            mockStore.makeTestEvent(calendarItemIdentifier: "evt-work", calendarIdentifier: "cal-work"),
        ]
    }

    @Test
    func sharesEveryCalendarByDefault() throws {
        #expect(try identifiers(provider.handle(operation: "list_lists", payloadJson: "{}"), key: "calendar_identifier")
            == ["list-home", "list-work"])
        #expect(try identifiers(provider.handle(operation: "list_reminders", payloadJson: "{}"))
            == ["rem-home", "rem-work"])
        #expect(try identifiers(provider.handle(operation: "list_events", payloadJson: Self.eventWindow))
            == ["evt-home", "evt-work"])
    }

    @Test
    func customReminderSelectionHidesUnsharedListsAndTheirReminders() throws {
        sharing.setSharedIdentifiers(["list-home"], for: .reminderLists)

        #expect(try identifiers(provider.handle(operation: "list_lists", payloadJson: "{}"), key: "calendar_identifier")
            == ["list-home"])
        #expect(try identifiers(provider.handle(operation: "list_reminders", payloadJson: "{}")) == ["rem-home"])

        let hiddenReminder = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-work"}"#
        )
        #expect(hiddenReminder.errorJson?.contains("Unknown calendar_item_identifier") == true)

        let createInHiddenList = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-work","title":"Task"}"#
        )
        #expect(createInHiddenList.errorJson?.contains("Unknown calendar_identifier") == true)

        // Event calendars keep their own default.
        #expect(try identifiers(provider.handle(operation: "list_events", payloadJson: Self.eventWindow))
            == ["evt-home", "evt-work"])
    }

    @Test
    func customEventSelectionHidesUnsharedCalendarsAndTheirEvents() throws {
        sharing.setSharedIdentifiers(["cal-work"], for: .eventCalendars)

        #expect(try identifiers(
            provider.handle(operation: "list_calendars", payloadJson: "{}"),
            key: "calendar_identifier"
        )
            == ["cal-work"])
        #expect(try identifiers(provider.handle(operation: "list_events", payloadJson: Self.eventWindow))
            == ["evt-work"])

        let hiddenEvent = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"evt-evt-home"}"#
        )
        #expect(hiddenEvent.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    func emptySelectionSharesNothing() throws {
        sharing.setSharedIdentifiers([], for: .reminderLists)

        #expect(try identifiers(provider.handle(operation: "list_reminders", payloadJson: "{}")).isEmpty)
    }

    @Test
    func listsCreatedThroughMCPJoinACustomSelection() throws {
        sharing.setSharedIdentifiers(["list-home"], for: .reminderLists)

        let created = provider.handle(operation: "create_list", payloadJson: #"{"title":"Groceries"}"#)
        let createdID = try #require(try object(created)["calendar_identifier"] as? String)

        #expect(sharing.sharedIdentifiers(for: .reminderLists) == ["list-home", createdID])
    }

    @Test
    func selectionPersistsAcrossLaunches() {
        sharing.setSharedIdentifiers(["list-home"], for: .reminderLists)
        sharing.setSharedIdentifiers(["cal-work"], for: .eventCalendars)
        sharing.setSharedIdentifiers(nil, for: .eventCalendars)

        let relaunched = CalendarSharingStore(defaults: defaults) { _ in [] }

        #expect(relaunched.sharedIdentifiers(for: .reminderLists) == ["list-home"])
        #expect(relaunched.sharedIdentifiers(for: .eventCalendars) == nil)
    }

    private static let eventWindow = #"{"start_date":"2023-11-14T00:00:00Z","end_date":"2023-11-16T00:00:00Z"}"#

    private func identifiers(_ response: ProviderResponse,
                             key: String = "calendar_item_identifier") throws -> [String]
    {
        #expect(response.ok, "\(response.errorJson ?? "")")
        let data = try #require(response.payloadJson.data(using: .utf8))
        let items = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return items.compactMap { $0[key] as? String }.sorted()
    }

    private func object(_ response: ProviderResponse) throws -> [String: Any] {
        #expect(response.ok, "\(response.errorJson ?? "")")
        let data = try #require(response.payloadJson.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

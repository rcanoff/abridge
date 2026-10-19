@testable import ABridge
import Foundation
import Testing

@Suite("EventKitProviderDelete")
struct EventKitProviderDeleteTests {
    @Test
    @MainActor
    func deleteReminderReturnsSuccessEnvelope() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-delete-1",
                calendarIdentifier: "list-delete",
                title: "Remove me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-delete-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_item_identifier\":\"rem-delete-1\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(!response.payloadJson.contains("\"reminder_id\""))
        #expect(mockStore.reminders.isEmpty)
    }

    @Test
    @MainActor
    func deleteReminderDoesNotTrimReminderIDForLookup() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-delete-1",
                calendarIdentifier: "list-delete",
                title: "Remove me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"calendar_item_identifier":" rem-delete-1 "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier:  rem-delete-1 ") == true)
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders.first?.calendarItemIdentifier == "rem-delete-1")
    }

    @Test
    @MainActor
    func deleteReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func deleteReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func deleteReminderByUniqueTitleRemovesThatReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "groceries", title: "Groceries")]
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-milk",
            calendarIdentifier: "groceries",
            title: "Buy Milk"
        )
        reminder.calendar?.title = "Groceries"
        mockStore.reminders = [reminder]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_title":"buy milk"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_item_identifier\":\"rem-milk\""))
        #expect(mockStore.reminders.isEmpty)
    }

    @Test
    @MainActor
    func deleteReminderByTitleRefusesAmbiguousMatches() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [
            mockStore.makeTestCalendar(calendarIdentifier: "groceries", title: "Groceries"),
            mockStore.makeTestCalendar(calendarIdentifier: "work", title: "Work"),
        ]
        let groceries = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-g",
            calendarIdentifier: "groceries",
            title: "Buy milk"
        )
        groceries.calendar?.title = "Groceries"
        groceries.dueDateComponents = DateComponents(year: 2026, month: 10, day: 26)
        let work = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-w",
            calendarIdentifier: "work",
            title: "BUY MILK",
            isCompleted: true
        )
        work.calendar?.title = "Work"
        mockStore.reminders = [work, groceries]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_title":"Buy milk"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("reminder_title_ambiguous") == true)
        #expect(response.errorJson?.contains("rem-g in Groceries, due 2026-10-26, completed false") == true)
        #expect(response.errorJson?.contains("rem-w in Work, completed true") == true)
        #expect(mockStore.reminders.count == 2)
    }

    @Test
    @MainActor
    func deleteReminderByTitleCanScopeToOneList() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [
            mockStore.makeTestCalendar(calendarIdentifier: "groceries", title: "Groceries"),
            mockStore.makeTestCalendar(calendarIdentifier: "work", title: "Work"),
        ]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-g",
                calendarIdentifier: "groceries",
                title: "Buy milk"
            ),
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-w",
                calendarIdentifier: "work",
                title: "Buy milk"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_title":"Buy milk","calendar_identifier":"work"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.reminders.map(\.calendarItemIdentifier) == ["rem-g"])
    }

    @Test
    @MainActor
    func deleteReminderByMissingTitleReturnsNotFound() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "groceries")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-g",
                calendarIdentifier: "groceries",
                title: "Other"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_reminder",
            payloadJson: #"{"reminder_title":"Buy milk"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("not_found") == true)
        #expect(mockStore.reminders.count == 1)
    }
}

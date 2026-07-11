@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderUpdate")
struct EventKitProviderUpdateTests {
    @Test
    @MainActor
    func updateReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-update")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-update-1",
                calendarIdentifier: "list-update",
                title: "Original title",
                notes: "keep me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-update-1","title":"Updated title"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Updated title"))
        #expect(response.payloadJson.contains("keep me"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].title == "Updated title")
        #expect(mockStore.reminders[0].notes == "keep me")
    }

    @Test
    @MainActor
    func updateReminderAppliesOptionalFields() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-update-2")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-update-2",
                calendarIdentifier: "list-update-2",
                title: "Task"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let payloadJson = """
        {"calendar_item_identifier":"rem-update-2","notes":"Updated notes","priority":3,\
        "due_date_components":{"year":2026,"month":7,"day":1}}
        """
        let response = provider.handle(operation: "update_reminder", payloadJson: payloadJson)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Updated notes"))
        #expect(response.payloadJson.contains("\"priority\":3"))
        #expect(response.payloadJson.contains("due_date_components"))
        #expect(mockStore.reminders[0].notes == "Updated notes")
        #expect(mockStore.reminders[0].priority == 3)
    }

    @Test
    @MainActor
    func updateReminderMovesCalendarWhenCalendarIdentifierProvided() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let sourceList = mockStore.makeTestCalendar(calendarIdentifier: "list-a", title: "A")
        let targetList = mockStore.makeTestCalendar(calendarIdentifier: "list-b", title: "B")
        mockStore.calendars = [sourceList, targetList]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-move",
                calendarIdentifier: "list-a",
                title: "Move me"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-move","calendar_identifier":"list-b"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("list-b"))
        #expect(mockStore.reminders[0].calendar?.calendarIdentifier == "list-b")
    }

    @Test
    @MainActor
    func updateReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing","title":"Nope"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func updateReminderUnknownCalendarReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-known")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-bad-cal",
                calendarIdentifier: "list-known",
                title: "Task"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-bad-cal","calendar_identifier":"missing-list"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func updateReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1","title":"Task"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

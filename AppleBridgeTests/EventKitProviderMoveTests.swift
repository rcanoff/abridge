@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderMove")
struct EventKitProviderMoveTests {
    @Test
    @MainActor
    func moveReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let sourceList = mockStore.makeTestCalendar(calendarIdentifier: "list-source", title: "Source")
        let targetList = mockStore.makeTestCalendar(calendarIdentifier: "list-target", title: "Target")
        mockStore.calendars = [sourceList, targetList]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-move-1",
                calendarIdentifier: "list-source",
                title: "Move me",
                notes: "unchanged"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-move-1","calendar_identifier":"list-target"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Move me"))
        #expect(response.payloadJson.contains("unchanged"))
        #expect(response.payloadJson.contains("list-target"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].calendar?.calendarIdentifier == "list-target")
        #expect(mockStore.reminders[0].title == "Move me")
        #expect(mockStore.reminders[0].notes == "unchanged")
    }

    @Test
    @MainActor
    func moveReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing","calendar_identifier":"list-target"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func moveReminderUnknownCalendarReturnsInvalidArguments() {
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
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-bad-cal","calendar_identifier":"missing-list"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func moveReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1","calendar_identifier":"list-target"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

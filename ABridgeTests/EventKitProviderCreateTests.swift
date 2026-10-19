@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderCreate")
struct EventKitProviderCreateTests {
    @Test
    @MainActor
    func createReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create","title":"New task","notes":"detail"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("New task"))
        #expect(response.payloadJson.contains("list-create"))
        #expect(response.payloadJson.contains("detail"))
        #expect(mockStore.reminders.count == 1)
    }

    @Test
    @MainActor
    func createReminderAppliesOptionalFields() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-2")]
        let provider = EventKitProvider(store: mockStore)

        let payloadJson = """
        {"calendar_identifier":"list-create-2","title":"Priority task","priority":5,\
        "due_date_components":{"year":2026,"month":6,"day":28}}
        """
        let response = provider.handle(operation: "create_reminder", payloadJson: payloadJson)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"priority\":5"))
        #expect(response.payloadJson.contains("due_date_components"))
        #expect(response.payloadJson.contains("2026"))
    }

    @Test
    @MainActor
    func createReminderTimedDueWithoutTimeZoneStaysFloating() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-float")]
        let provider = EventKitProvider(store: mockStore)

        let payloadJson = """
        {"calendar_identifier":"list-float","title":"Floating","time_zone":"America/New_York",\
        "due_date_components":{"year":2026,"month":10,"day":19,"hour":9,"minute":0}}
        """
        let response = provider.handle(operation: "create_reminder", payloadJson: payloadJson)

        #expect(response.ok == true)
        let due = mockStore.reminders[0].dueDateComponents
        #expect(due?.year == 2026)
        #expect(due?.hour == 9)
        #expect(due?.minute == 0)
        #expect(due?.timeZone == nil)
    }

    @Test
    @MainActor
    func createReminderUnknownCalendarReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"missing-list","title":"Task"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func createReminderPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create","title":"Task"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

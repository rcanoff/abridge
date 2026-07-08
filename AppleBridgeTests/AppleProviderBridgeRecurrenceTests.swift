@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeRecurrence")
struct AppleProviderBridgeRecurrenceTests {
    @Test
    @MainActor
    func routesEventKitSetReminderRecurrence() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-recurrence")]
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "r-recurrence",
            calendarIdentifier: "list-recurrence",
            title: "Task"
        )
        reminder.dueDateComponents = DateComponents(year: 2026, month: 7, day: 15, hour: 9, minute: 0)
        mockStore.reminders = [reminder]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"r-recurrence","recurrence_rules":[{"frequency":"daily"}]}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("frequency"))
    }
}

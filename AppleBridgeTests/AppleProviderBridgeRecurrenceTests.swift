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
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-recurrence",
                calendarIdentifier: "list-recurrence",
                title: "Task"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "set_reminder_recurrence",
            payloadJson: #"{"reminder_id":"r-recurrence","recurrence_rules":[{"frequency":"daily"}]}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("frequency"))
    }
}

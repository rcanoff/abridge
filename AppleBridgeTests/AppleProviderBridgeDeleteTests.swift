@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeDelete")
struct AppleProviderBridgeDeleteTests {
    @Test
    @MainActor
    func routesEventKitDeleteReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-delete",
                calendarIdentifier: "list-delete",
                title: "Gone"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "delete_reminder",
            payloadJson: #"{"reminder_id":"r-delete"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_item_identifier\":\"r-delete\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
    }
}

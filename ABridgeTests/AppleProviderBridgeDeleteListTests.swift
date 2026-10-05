@testable import ABridge
import Foundation
import Testing

@Suite("AppleProviderBridgeDeleteList")
struct AppleProviderBridgeDeleteListTests {
    @Test
    @MainActor
    func routesEventKitDeleteList() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-delete")]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "delete_list",
            payloadJson: #"{"calendar_identifier":"list-delete"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"calendar_identifier\":\"list-delete\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(mockStore.calendars.isEmpty)
    }
}

@testable import ABridge
import Foundation
import Testing

@Suite("AppleProviderBridgeListCalendars")
struct AppleProviderBridgeListCalendarsTests {
    @Test
    @MainActor
    func routesEventKitListCalendars() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_calendars",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
    }

    @Test
    @MainActor
    func listCalendarsWriteOnlyAuthorizationIsInsufficientForRead() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .writeOnly
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_calendars",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

import Foundation
import Testing
@testable import AppleBridge

@Suite("AppleProviderBridge")
struct AppleProviderBridgeTests {
    @Test
    func routesEventKitListLists() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_lists",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
    }

    @Test
    func unknownProviderReturnsError() {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(
            provider: "unknown",
            operation: "noop",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("unknown_provider") == true)
    }
}
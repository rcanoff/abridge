import Foundation
import Testing
@testable import AppleBridge

@Suite("AppleProviderBridge")
struct AppleProviderBridgeTests {
    @Test
    func callProviderReturnsNotImplemented() {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_reminders",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("not_implemented") == true)
    }
}
@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeContacts")
struct AppleProviderBridgeContactsTests {
    @Test
    func callProviderContactsReturnsUnknownOperation() {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(provider: "contacts", operation: "list_contacts", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("unknown_operation") == true)
    }
}

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

    @Test
    func callProviderContactsUnknownOperationWithQuoteProducesValidJSON() throws {
        let bridge = AppleProviderBridge()
        let operation = #"evil"operation"#
        let request = ProviderRequest(provider: "contacts", operation: operation, payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains(operation) == true)
    }
}

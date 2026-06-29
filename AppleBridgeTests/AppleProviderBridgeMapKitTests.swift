@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeMapKit")
struct AppleProviderBridgeMapKitTests {
    @Test
    func callProviderMapKitReturnsUnknownOperation() throws {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(provider: "mapkit", operation: "search_places", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains("search_places") == true)
    }
}
@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeVision")
struct AppleProviderBridgeVisionTests {
    @Test
    func callProviderVisionReturnsUnknownOperation() throws {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(provider: "vision", operation: "recognize_text", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains("recognize_text") == true)
    }
}

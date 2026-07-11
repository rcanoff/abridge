@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderRecognizeText")
struct VisionProviderRecognizeTextTests {
    @Test
    @MainActor
    func recognizeTextRequiresImageData_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func recognizeTextRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func recognizeTextReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let store = MockVisionStore()
        store.observations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
        #expect(results?.first?.keys.contains("candidates") == true)
    }

    @Test
    @MainActor
    func recognizeTextForwardsMaxCandidateCountToSerialization() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let store = MockVisionStore()
        store.observations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)","max_candidate_count":2}"#
        )

        #expect(store.lastRequest?.maxCandidateCount == 2)
    }
}

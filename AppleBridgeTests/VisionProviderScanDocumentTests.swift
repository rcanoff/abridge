@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderScanDocument")
struct VisionProviderScanDocumentTests {
    @Test
    @MainActor
    func scanDocumentRequiresImageData() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(operation: "scan_document", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("image_data") == true)
    }

    @Test
    @MainActor
    func scanDocumentRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "scan_document",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func scanDocumentReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "scan_document",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
        #expect(decoded?["segmentation"] is NSNull)
    }

    @Test
    @MainActor
    func scanDocumentForwardsIncludeSegmentationToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "scan_document",
            payloadJson: #"{"image_data":"\#(encoded)","include_segmentation":true}"#
        )

        #expect(store.lastScanDocumentRequest?.includeSegmentation == true)
    }

    @Test
    @MainActor
    func scanDocumentForwardsMaximumCandidateCountToSerialization() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "scan_document",
            payloadJson: #"{"image_data":"\#(encoded)","text_recognition_options":{"maximum_candidate_count":2}}"#
        )

        #expect(store.lastScanDocumentRequest?.maximumCandidateCount == 2)
        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = try #require(decoded?["results"] as? [[String: Any]])
        let document = try #require(results.first?["document"] as? [String: Any])
        let text = try #require(document["text"] as? [String: Any])
        let lines = try #require(text["lines"] as? [[String: Any]])
        let candidates = lines.first?["candidates"] as? [[String: Any]]
        #expect((candidates?.count ?? 0) <= 2)
    }
}

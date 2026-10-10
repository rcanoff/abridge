@testable import ABridge
import Foundation
import Testing

@Suite("AppleProviderBridgeVision")
struct AppleProviderBridgeVisionTests {
    @Test
    @MainActor
    func callProviderVisionRecognizeTextSucceedsWithMockStore() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let store = MockVisionStore()
        store.observations = observations
        let bridge = AppleProviderBridge(visionProvider: VisionProvider(store: store))
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let request = ProviderRequest(
            provider: "vision",
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    @MainActor
    func callProviderVisionRecognizeDocumentsSucceedsWithMockStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let bridge = AppleProviderBridge(visionProvider: VisionProvider(store: store))
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let request = ProviderRequest(
            provider: "vision",
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    @MainActor
    func callProviderVisionDetectBarcodesSucceedsWithMockStore() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let store = MockVisionStore()
        store.detectBarcodesObservations = observations
        let bridge = AppleProviderBridge(visionProvider: VisionProvider(store: store))
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let request = ProviderRequest(
            provider: "vision",
            operation: "detect_barcodes",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    @MainActor
    func callProviderVisionDetectFaceLandmarksSucceedsWithMockStore() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let store = MockVisionStore()
        store.faceObservations = observations
        let bridge = AppleProviderBridge(visionProvider: VisionProvider(store: store))
        let imageData = try VisionTestFixtures.samplePortraitImageData()
        let encoded = imageData.base64EncodedString()

        let request = ProviderRequest(
            provider: "vision",
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }
}

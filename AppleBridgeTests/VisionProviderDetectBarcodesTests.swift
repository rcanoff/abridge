@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderDetectBarcodes")
struct VisionProviderDetectBarcodesTests {
    @Test
    @MainActor
    func detectBarcodesRequiresImageData() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(operation: "detect_barcodes", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("image_data") == true)
    }

    @Test
    @MainActor
    func detectBarcodesRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "detect_barcodes",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func detectBarcodesReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let store = MockVisionStore()
        store.detectBarcodesObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "detect_barcodes",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    @MainActor
    func detectBarcodesForwardsOptionalArgumentsToStore() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let store = MockVisionStore()
        store.detectBarcodesObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "detect_barcodes",
            payloadJson: #"""
            {"image_data":"\#(
                encoded
            )","symbologies":["qr"],"region_of_interest":{"origin":{"x":0.1,"y":0.2},"size":{"width":0.5,"height":0.6}},"coalesce_composite_symbologies":true}
            """#
        )

        #expect(store.lastDetectBarcodesRequest?.symbologies?.count == 1)
        #expect(store.lastDetectBarcodesRequest?.regionOfInterest != nil)
        #expect(store.lastDetectBarcodesRequest?.coalesceCompositeSymbologies == true)
    }
}

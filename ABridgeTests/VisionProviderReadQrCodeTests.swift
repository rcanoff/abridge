@testable import ABridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderReadQrCode")
struct VisionProviderReadQrCodeTests {
    @Test
    @MainActor
    func readQrCodeRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "read_qr_code",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func readQrCodeReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleVNBarcodeObservations()
        let store = MockVisionStore()
        store.readQrCodeObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "read_qr_code",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
        #expect(results?.first?.keys.contains("symbology") == true)
        #expect(results?.first?.keys.contains("payload_string_value") == true)
    }

    @Test
    @MainActor
    func readQrCodeForwardsRegionOfInterestToStore() throws {
        let observations = try VisionTestFixtures.sampleVNBarcodeObservations()
        let store = MockVisionStore()
        store.readQrCodeObservations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let region =
            #"{"origin":{"x":0.1,"y":0.2},"size":{"width":0.5,"height":0.6}}"#
        let payload = #"{"image_data":"\#(encoded)","region_of_interest":\#(region)}"#
        _ = provider.handle(operation: "read_qr_code", payloadJson: payload)

        #expect(store.lastReadQrCodeRequest?.regionOfInterest == CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6))
    }
}

@testable import ABridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderScanDocument")
struct VisionProviderScanDocumentTests {
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

    @Test
    @MainActor
    func scanDocumentForwardsTextRecognitionOptionsToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"minimum_text_height_fraction":0.02,"automatically_detect_language":true,"recognition_languages":["en-US"],"use_language_correction":false,"custom_words":["Invoice"]}}"#
        let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")

        let options = try #require(store.lastScanDocumentRequest?.textRecognitionOptions)
        #expect(options.minimumTextHeightFraction == 0.02)
        #expect(options.automaticallyDetectLanguage == true)
        #expect(options.recognitionLanguages.count == 1)
        #expect(options.useLanguageCorrection == false)
        #expect(options.customWords == ["Invoice"])
    }

    @Test
    @MainActor
    func scanDocumentForwardsRecognitionLanguagesToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"recognition_languages":["en-US"]}}"#
        let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")
        #expect(store.lastScanDocumentRequest?.textRecognitionOptions?.recognitionLanguages.count == 1)
    }

    @Test
    @MainActor
    func scanDocumentForwardsBarcodeDetectionOptionsToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","barcode_detection_options":{"enabled":true,"symbologies":["qr"],"coalesce_composite_symbologies":true}}"#
        let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")

        let options = try #require(store.lastScanDocumentRequest?.barcodeDetectionOptions)
        #expect(options.enabled == true)
        #expect(options.symbologies.count == 1)
        #expect(options.coalesceCompositeSymbologies == true)
    }

    @Test
    @MainActor
    func scanDocumentForwardsValidRegionOfInterestToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.scanDocumentResult = VisionScanDocumentResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","region_of_interest":{"origin":{"x":0.1,"y":0.2},"size":{"width":0.5,"height":0.6}}}"#
        let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")
        #expect(store.lastScanDocumentRequest?.regionOfInterest != nil)
    }

    @Test
    @MainActor
    func scanDocumentRejectsEmptyRecognitionLanguage() throws {
        let provider = VisionProvider(store: MockVisionStore())
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"recognition_languages":[""]}}"#
        let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("recognition_languages") == true)
    }

    @Test
    @MainActor
    func scanDocumentRejectsRegionOfInterestOutsideNormalizedBounds() throws {
        let provider = VisionProvider(store: MockVisionStore())
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        let outOfBoundsX = #"{"image_data":"\#(encoded)","region_of_interest":{"origin":{"x":-0.1,"y":0.2},"size":{"width":0.5,"height":0.5}}}"#
        // swiftlint:disable:next line_length
        let zeroWidth = #"{"image_data":"\#(encoded)","region_of_interest":{"origin":{"x":0.1,"y":0.2},"size":{"width":0,"height":0.5}}}"#
        // swiftlint:disable:next line_length
        let exceedsBounds = #"{"image_data":"\#(encoded)","region_of_interest":{"origin":{"x":0.6,"y":0.2},"size":{"width":0.5,"height":0.5}}}"#
        let cases = [outOfBoundsX, zeroWidth, exceedsBounds]

        for payloadJson in cases {
            let response = provider.handle(operation: "scan_document", payloadJson: payloadJson)
            #expect(response.ok == false)
            #expect(response.errorJson?.contains("invalid_arguments") == true)
            #expect(response.errorJson?.contains("region_of_interest") == true)
        }
    }
}

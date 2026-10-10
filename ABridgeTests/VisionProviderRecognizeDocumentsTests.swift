@testable import ABridge
import Foundation
import Testing
import Vision

@Suite("VisionProviderRecognizeDocuments")
struct VisionProviderRecognizeDocumentsTests {
    @Test
    @MainActor
    func recognizeDocumentsRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func recognizeDocumentsReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "recognize_documents",
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
    func recognizeDocumentsForwardsIncludeSegmentationToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"\#(encoded)","include_segmentation":true}"#
        )

        #expect(store.lastRecognizeDocumentsRequest?.includeSegmentation == true)
    }

    @Test
    @MainActor
    func recognizeDocumentsForwardsMaximumCandidateCountToSerialization() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"\#(encoded)","text_recognition_options":{"maximum_candidate_count":2}}"#
        )

        #expect(store.lastRecognizeDocumentsRequest?.maximumCandidateCount == 2)
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
    func recognizeDocumentsForwardsTextRecognitionOptionsToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"minimum_text_height_fraction":0.02,"automatically_detect_language":true,"recognition_languages":["en-US"],"use_language_correction":false,"custom_words":["Invoice"]}}"#
        let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")

        let options = try #require(store.lastRecognizeDocumentsRequest?.textRecognitionOptions)
        #expect(options.minimumTextHeightFraction == 0.02)
        #expect(options.automaticallyDetectLanguage == true)
        #expect(options.recognitionLanguages.count == 1)
        #expect(options.useLanguageCorrection == false)
        #expect(options.customWords == ["Invoice"])
    }

    @Test
    @MainActor
    func recognizeDocumentsForwardsRecognitionLanguagesToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"recognition_languages":["en-US"]}}"#
        let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")
        #expect(store.lastRecognizeDocumentsRequest?.textRecognitionOptions?.recognitionLanguages.count == 1)
    }

    @Test
    @MainActor
    func recognizeDocumentsForwardsBarcodeDetectionOptionsToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","barcode_detection_options":{"enabled":true,"symbologies":["qr"],"coalesce_composite_symbologies":true}}"#
        let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")

        let options = try #require(store.lastRecognizeDocumentsRequest?.barcodeDetectionOptions)
        #expect(options.enabled == true)
        #expect(options.symbologies.count == 1)
        #expect(options.coalesceCompositeSymbologies == true)
    }

    @Test
    @MainActor
    func recognizeDocumentsForwardsValidRegionOfInterestToStore() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let store = MockVisionStore()
        store.recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: observations, segmentation: nil)
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        // swiftlint:disable:next line_length
        // swiftlint:disable:next line_length
        let payloadJson = #"{"image_data":"\#(encoded)","region_of_interest":{"origin":{"x":0.1,"y":0.2},"size":{"width":0.5,"height":0.6}}}"#
        let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")
        #expect(store.lastRecognizeDocumentsRequest?.regionOfInterest != nil)
    }

    @Test
    @MainActor
    func recognizeDocumentsRejectsEmptyRecognitionLanguage() throws {
        let provider = VisionProvider(store: MockVisionStore())
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let payloadJson = #"{"image_data":"\#(encoded)","text_recognition_options":{"recognition_languages":[""]}}"#
        let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("recognition_languages") == true)
    }

    @Test
    @MainActor
    func recognizeDocumentsRejectsRegionOfInterestOutsideNormalizedBounds() throws {
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
            let response = provider.handle(operation: "recognize_documents", payloadJson: payloadJson)
            #expect(response.ok == false)
            #expect(response.errorJson?.contains("invalid_arguments") == true)
            #expect(response.errorJson?.contains("region_of_interest") == true)
        }
    }
}

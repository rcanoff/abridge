@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionSerialization")
struct VisionSerializationTests {
    private let observationKeys: [String] = [
        "uuid",
        "confidence",
        "time_range",
        "request_revision",
        "bounding_box",
        "global_segmentation_mask",
        "top_left",
        "top_right",
        "bottom_left",
        "bottom_right",
        "candidates",
    ]

    private let candidateKeys: [String] = [
        "string",
        "confidence",
        "request_revision",
    ]

    private let barcodeObservationKeys: [String] = [
        "uuid",
        "confidence",
        "time_range",
        "request_revision",
        "bounding_box",
        "global_segmentation_mask",
        "top_left",
        "top_right",
        "bottom_left",
        "bottom_right",
        "symbology",
        "payload_string_value",
        "payload_data",
    ]

    @Test
    @MainActor
    func recognizedTextObservationProjectionIncludesAllKeys() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let observation = try #require(observations.first)

        let object = VisionSerialization.recognizedTextObservationJSONObject(
            from: observation,
            maxCandidateCount: 1
        )

        for key in observationKeys {
            #expect(object.keys.contains(key), "Missing observation key: \(key)")
        }

        let candidates = try #require(object["candidates"] as? [[String: Any]])
        let firstCandidate = try #require(candidates.first)
        for key in candidateKeys {
            #expect(firstCandidate.keys.contains(key), "Missing candidate key: \(key)")
        }
    }

    @Test
    @MainActor
    func recognizeTextResponseWrapsResultsArray() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let object = VisionSerialization.recognizeTextResponseJSONObject(
            observations: observations,
            maxCandidateCount: 1
        )

        #expect(object.keys.contains("results"))
        let results = object["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    func optionalTimeRangeSerializesAsNull() {
        let value = VisionSerialization.cmTimeRangeJSONObject(from: nil as CMTimeRange?)
        #expect(value is NSNull)
    }

    @Test
    @MainActor
    func barcodeObservationProjectionIncludesAllKeys() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let observation = try #require(observations.first)

        let object = VisionSerialization.barcodeObservationJSONObject(from: observation)

        for key in barcodeObservationKeys {
            #expect(object.keys.contains(key), "Missing observation key: \(key)")
        }
    }

    @Test
    @MainActor
    func readQrCodeResponseWrapsResultsArray() throws {
        let observations = try VisionTestFixtures.sampleBarcodeObservations()
        let object = VisionSerialization.readQrCodeResponseJSONObject(observations: observations)

        #expect(object.keys.contains("results"))
        let results = object["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
    }

    @Test
    @MainActor
    func maxCandidateCountLimitsSerializedCandidates() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let observation = try #require(observations.first)

        let object = VisionSerialization.recognizedTextObservationJSONObject(
            from: observation,
            maxCandidateCount: 3
        )
        let candidates = object["candidates"] as? [[String: Any]]
        #expect((candidates?.count ?? 0) <= 3)
    }
}

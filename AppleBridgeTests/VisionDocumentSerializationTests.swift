@testable import AppleBridge
import Foundation
import Testing
import Vision

@Suite("VisionDocumentSerialization")
struct VisionDocumentSerializationTests {
    private let documentObservationKeys = [
        "uuid",
        "confidence",
        "time_range",
        "originating_request_descriptor",
        "document",
    ]

    private let containerKeys = [
        "title",
        "text",
        "paragraphs",
        "tables",
        "lists",
        "barcodes",
        "bounding_region",
    ]

    private let textKeys = [
        "transcript",
        "text_alignment",
        "detected_data",
        "lines",
        "words",
        "bounding_region",
    ]

    private let swiftTextObservationKeys = [
        "uuid",
        "confidence",
        "time_range",
        "originating_request_descriptor",
        "top_left",
        "top_right",
        "bottom_right",
        "bottom_left",
        "bounding_region",
        "transcript",
        "recognition_languages",
        "is_title",
        "should_wrap_to_next_line",
        "text_direction",
        "candidates",
    ]

    @Test
    @MainActor
    func scanDocumentResponseIncludesTopLevelKeys() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let object = VisionSerialization.scanDocumentResponseJSONObject(
            observations: observations,
            segmentation: nil,
            maximumCandidateCount: 1
        )

        #expect(object.keys.contains("results"))
        #expect(object.keys.contains("segmentation"))
        #expect(object["segmentation"] is NSNull)
    }

    @Test
    @MainActor
    func documentObservationProjectionIncludesAllKeys() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let observation = try #require(observations.first)
        let object = VisionSerialization.documentObservationJSONObject(
            from: observation,
            maximumCandidateCount: 1
        )

        for key in documentObservationKeys {
            #expect(object.keys.contains(key), "Missing document observation key: \(key)")
        }

        let document = try #require(object["document"] as? [String: Any])
        for key in containerKeys {
            #expect(document.keys.contains(key), "Missing container key: \(key)")
        }

        let text = try #require(document["text"] as? [String: Any])
        for key in textKeys {
            #expect(text.keys.contains(key), "Missing text key: \(key)")
        }

        let lines = try #require(text["lines"] as? [[String: Any]])
        let firstLine = try #require(lines.first)
        for key in swiftTextObservationKeys {
            #expect(firstLine.keys.contains(key), "Missing swift text observation key: \(key)")
        }
        #expect(firstLine.keys.contains("transcript"))
        #expect(firstLine.keys.contains("bounding_region"))
        #expect(!firstLine.keys.contains("request_revision"))
    }

    @Test
    @MainActor
    func maximumCandidateCountLimitsNestedCandidates() throws {
        let observations = try VisionTestFixtures.sampleDocumentObservations()
        let observation = try #require(observations.first)
        let object = VisionSerialization.documentObservationJSONObject(
            from: observation,
            maximumCandidateCount: 2
        )
        let document = try #require(object["document"] as? [String: Any])
        let text = try #require(document["text"] as? [String: Any])
        let lines = try #require(text["lines"] as? [[String: Any]])
        let firstLine = try #require(lines.first)
        let candidates = firstLine["candidates"] as? [[String: Any]]
        #expect((candidates?.count ?? 0) <= 2)
    }
}

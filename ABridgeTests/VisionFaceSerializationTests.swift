@testable import ABridge
import Foundation
import Testing
import Vision

@Suite("VisionFaceSerialization")
struct VisionFaceSerializationTests {
    private let responseKeys = ["results"]

    private let faceObservationKeys = [
        "uuid",
        "confidence",
        "time_range",
        "request_revision",
        "bounding_box",
        "global_segmentation_mask",
        "roll",
        "yaw",
        "pitch",
        "face_capture_quality",
        "landmarks",
    ]

    private let landmarkKeys = [
        "confidence",
        "request_revision",
        "all_points",
        "face_contour",
        "left_eye",
        "right_eye",
        "left_eyebrow",
        "right_eyebrow",
        "nose",
        "nose_crest",
        "median_line",
        "outer_lips",
        "inner_lips",
        "left_pupil",
        "right_pupil",
    ]

    private let landmarkRegionKeys = [
        "point_count",
        "request_revision",
        "normalized_points",
        "precision_estimates_per_point",
        "points_classification",
    ]

    @Test
    @MainActor
    func detectFaceLandmarksResponseIncludesTopLevelKeys() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let object = VisionFaceSerialization.detectFaceLandmarksResponseJSONObject(observations: observations)

        for key in responseKeys {
            #expect(object.keys.contains(key), "Missing response key: \(key)")
        }
    }

    @Test
    @MainActor
    func faceObservationProjectionIncludesAllKeys() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let observation = try #require(observations.first)
        let object = VisionFaceSerialization.faceObservationJSONObject(from: observation)

        for key in faceObservationKeys {
            #expect(object.keys.contains(key), "Missing face observation key: \(key)")
        }
    }

    @Test
    @MainActor
    func faceLandmarksProjectionIncludesAllKeysWhenPresent() throws {
        let observations = try VisionTestFixtures.sampleFaceObservations()
        let observation = try #require(observations.first)
        guard let landmarks = observation.landmarks else {
            return
        }

        let object = VisionFaceSerialization.faceLandmarksJSONObject(from: landmarks) as? [String: Any]
        let landmarksObject = try #require(object)

        for key in landmarkKeys {
            #expect(landmarksObject.keys.contains(key), "Missing landmark key: \(key)")
        }

        if let regionObject = firstNonNullLandmarkRegion(in: landmarksObject) {
            for key in landmarkRegionKeys {
                #expect(regionObject.keys.contains(key), "Missing landmark region key: \(key)")
            }
        }
    }

    private func firstNonNullLandmarkRegion(in landmarksObject: [String: Any]) -> [String: Any]? {
        for key in landmarkKeys where key != "confidence" && key != "request_revision" {
            if let region = landmarksObject[key] as? [String: Any] {
                return region
            }
        }
        return nil
    }
}

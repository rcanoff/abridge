import Foundation
import Vision

enum VisionFaceSerialization {
    static func detectFaceLandmarksResponseJSONObject(observations: [VNFaceObservation]) -> [String: Any] {
        ["results": observations.map(faceObservationJSONObject(from:))]
    }

    static func faceObservationJSONObject(from observation: VNFaceObservation) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "request_revision": observation.requestRevision,
            "bounding_box": VisionSerialization.cgRectJSONObject(from: observation.boundingBox),
            "global_segmentation_mask": VisionSerialization.pixelBufferObservationJSONObject(
                from: observation.globalSegmentationMask
            ),
            "roll": VisionSerialization.jsonValue(observation.roll),
            "yaw": VisionSerialization.jsonValue(observation.yaw),
            "pitch": VisionSerialization.jsonValue(observation.pitch),
            "face_capture_quality": VisionSerialization.jsonValue(observation.faceCaptureQuality),
            "landmarks": faceLandmarksJSONObject(from: observation.landmarks),
        ]
    }

    static func faceLandmarksJSONObject(from landmarks: VNFaceLandmarks2D?) -> Any {
        guard let landmarks else { return NSNull() }

        return [
            "confidence": landmarks.confidence,
            "request_revision": landmarks.requestRevision,
            "all_points": faceLandmarkRegionJSONObject(from: landmarks.allPoints),
            "face_contour": faceLandmarkRegionJSONObject(from: landmarks.faceContour),
            "left_eye": faceLandmarkRegionJSONObject(from: landmarks.leftEye),
            "right_eye": faceLandmarkRegionJSONObject(from: landmarks.rightEye),
            "left_eyebrow": faceLandmarkRegionJSONObject(from: landmarks.leftEyebrow),
            "right_eyebrow": faceLandmarkRegionJSONObject(from: landmarks.rightEyebrow),
            "nose": faceLandmarkRegionJSONObject(from: landmarks.nose),
            "nose_crest": faceLandmarkRegionJSONObject(from: landmarks.noseCrest),
            "median_line": faceLandmarkRegionJSONObject(from: landmarks.medianLine),
            "outer_lips": faceLandmarkRegionJSONObject(from: landmarks.outerLips),
            "inner_lips": faceLandmarkRegionJSONObject(from: landmarks.innerLips),
            "left_pupil": faceLandmarkRegionJSONObject(from: landmarks.leftPupil),
            "right_pupil": faceLandmarkRegionJSONObject(from: landmarks.rightPupil),
        ]
    }

    static func faceLandmarkRegionJSONObject(from region: VNFaceLandmarkRegion2D?) -> Any {
        guard let region else { return NSNull() }

        return [
            "point_count": region.pointCount,
            "request_revision": region.requestRevision,
            "normalized_points": region.normalizedPoints.map(VisionSerialization.cgPointJSONObject(from:)),
            "precision_estimates_per_point": precisionEstimatesJSONObject(from: region.precisionEstimatesPerPoint),
            "points_classification": pointsClassificationString(from: region.pointsClassification),
        ]
    }

    private static func precisionEstimatesJSONObject(from estimates: [Float]?) -> Any {
        guard let estimates else { return NSNull() }
        return estimates.map { Double($0) }
    }

    private static func pointsClassificationString(from classification: VNPointsClassification) -> String {
        switch classification {
        case .disconnected:
            "disconnected"
        case .openPath:
            "open_path"
        case .closedPath:
            "closed_path"
        @unknown default:
            "disconnected"
        }
    }
}

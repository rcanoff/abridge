import Foundation
import Vision

enum VisionBarcodeSerialization {
    static func detectBarcodesResponseJSONObject(observations: [BarcodeObservation]) throws -> [String: Any] {
        try [
            "results": observations.map(barcodeObservationJSONObject(from:)),
        ]
    }

    static func barcodeObservationJSONObject(from observation: BarcodeObservation) throws -> [String: Any] {
        try VisionDocumentObservationSerialization.barcodeObservationJSONObject(
            from: observation,
            boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: observation.boundingRegion
            )
        )
    }
}

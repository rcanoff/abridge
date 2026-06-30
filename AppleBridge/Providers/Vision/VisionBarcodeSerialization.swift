import Foundation
import Vision

enum VisionBarcodeSerialization {
    static func detectBarcodesResponseJSONObject(observations: [BarcodeObservation]) -> [String: Any] {
        [
            "results": observations.map(barcodeObservationJSONObject(from:)),
        ]
    }

    static func barcodeObservationJSONObject(from observation: BarcodeObservation) -> [String: Any] {
        VisionDocumentObservationSerialization.barcodeObservationJSONObject(
            from: observation,
            boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: observation.boundingRegion
            )
        )
    }
}

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Vision

enum VisionSerialization {
    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw VisionProviderError.serializationFailed
        }
        return string
    }

    static func recognizeTextResponseJSONObject(
        observations: [VNRecognizedTextObservation],
        maxCandidateCount: Int
    ) -> [String: Any] {
        [
            "results": observations.map {
                recognizedTextObservationJSONObject(from: $0, maxCandidateCount: maxCandidateCount)
            },
        ]
    }

    static func recognizedTextObservationJSONObject(
        from observation: VNRecognizedTextObservation,
        maxCandidateCount: Int
    ) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": cmTimeRangeJSONObject(from: observation.timeRange),
            "request_revision": observation.requestRevision,
            "bounding_box": cgRectJSONObject(from: observation.boundingBox),
            "global_segmentation_mask": pixelBufferObservationJSONObject(from: observation.globalSegmentationMask),
            "top_left": cgPointJSONObject(from: observation.topLeft),
            "top_right": cgPointJSONObject(from: observation.topRight),
            "bottom_left": cgPointJSONObject(from: observation.bottomLeft),
            "bottom_right": cgPointJSONObject(from: observation.bottomRight),
            "candidates": observation.topCandidates(maxCandidateCount).map(recognizedTextJSONObject(from:)),
        ]
    }

    static func recognizedTextJSONObject(from text: VNRecognizedText) -> [String: Any] {
        [
            "string": text.string,
            "confidence": text.confidence,
            "request_revision": text.requestRevision,
        ]
    }

    static func cgRectJSONObject(from rect: CGRect) -> [String: Any] {
        [
            "origin": cgPointJSONObject(from: rect.origin),
            "size": [
                "width": rect.size.width,
                "height": rect.size.height,
            ],
        ]
    }

    static func cgPointJSONObject(from point: CGPoint) -> [String: Any] {
        [
            "x": point.x,
            "y": point.y,
        ]
    }

    static func cmTimeRangeJSONObject(from range: CMTimeRange) -> [String: Any] {
        [
            "start_seconds": CMTimeGetSeconds(range.start),
            "duration_seconds": CMTimeGetSeconds(range.duration),
        ]
    }

    static func pixelBufferObservationJSONObject(from observation: VNPixelBufferObservation?) -> Any {
        guard let observation else { return NSNull() }

        return [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": cmTimeRangeJSONObject(from: observation.timeRange),
            "request_revision": observation.requestRevision,
            "pixel_buffer": pixelBufferJSONObject(from: observation.pixelBuffer),
            "feature_name": jsonValue(observation.featureName),
        ]
    }

    static func pixelBufferJSONObject(from pixelBuffer: CVPixelBuffer?) -> Any {
        guard let pixelBuffer else { return NSNull() }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            if lockStatus == kCVReturnSuccess {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }
        }

        var dataValue: Any = NSNull()
        if lockStatus == kCVReturnSuccess {
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
            if planeCount > 0 {
                if let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                    let length = bytesPerRow * height
                    let data = Data(bytes: baseAddress, count: length)
                    dataValue = data.base64EncodedString()
                }
            } else if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let length = bytesPerRow * height
                let data = Data(bytes: baseAddress, count: length)
                dataValue = data.base64EncodedString()
            }
        }

        return [
            "width": width,
            "height": height,
            "pixel_format": fourCCString(from: pixelFormat),
            "bytes_per_row": bytesPerRow,
            "data": dataValue,
        ]
    }

    static func jsonValue(_ string: String?) -> Any {
        string ?? NSNull()
    }

    private static func fourCCString(from pixelFormat: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((pixelFormat >> 24) & 0xFF),
            UInt8((pixelFormat >> 16) & 0xFF),
            UInt8((pixelFormat >> 8) & 0xFF),
            UInt8(pixelFormat & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "%08x", pixelFormat)
    }
}
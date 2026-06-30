import CoreGraphics
import CoreVideo
import Foundation
import Vision

enum VisionDocumentObservationSerialization {
    static func recognizedTextObservationJSONObject(
        from observation: RecognizedTextObservation,
        maximumCandidateCount: Int,
        boundingRegion: [String: Any]
    ) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "originating_request_descriptor": requestDescriptorJSONObject(
                from: observation.originatingRequestDescriptor
            ),
            "top_left": normalizedPointJSONObject(from: observation.topLeft),
            "top_right": normalizedPointJSONObject(from: observation.topRight),
            "bottom_right": normalizedPointJSONObject(from: observation.bottomRight),
            "bottom_left": normalizedPointJSONObject(from: observation.bottomLeft),
            "bounding_region": boundingRegion,
            "transcript": observation.transcript,
            "recognition_languages": observation.recognitionLanguages.map(bcp47String(from:)),
            "is_title": observation.isTitle,
            "should_wrap_to_next_line": observation.shouldWrapToNextLine ?? NSNull(),
            "text_direction": textDirectionString(from: observation.textDirection) ?? NSNull(),
            "candidates": observation.topCandidates(maximumCandidateCount).map(recognizedTextJSONObject(from:)),
        ]
    }

    static func barcodeObservationJSONObject(
        from observation: BarcodeObservation,
        boundingRegion: [String: Any]
    ) throws -> [String: Any] {
        try [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "originating_request_descriptor": requestDescriptorJSONObject(
                from: observation.originatingRequestDescriptor
            ),
            "payload_string": VisionSerialization.jsonValue(observation.payloadString),
            "payload_data": base64DataValue(observation.payloadData),
            "supplemental_payload_string": VisionSerialization.jsonValue(observation.supplementalPayloadString),
            "supplemental_payload_data": base64DataValue(observation.supplementalPayloadData),
            "supplemental_composite_type": compositeTypeString(from: observation.supplementalCompositeType) ?? NSNull(),
            "is_gs1_data_carrier": observation.isGS1DataCarrier,
            "symbology": barcodeSymbologyIdentifier(from: observation.symbology),
            "is_color_inverted": observation.isColorInverted,
            "top_left": normalizedPointJSONObject(from: observation.topLeft),
            "top_right": normalizedPointJSONObject(from: observation.topRight),
            "bottom_right": normalizedPointJSONObject(from: observation.bottomRight),
            "bottom_left": normalizedPointJSONObject(from: observation.bottomLeft),
            "bounding_region": boundingRegion,
        ]
    }

    static func detectedDocumentObservationJSONObject(from observation: DetectedDocumentObservation) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "originating_request_descriptor": requestDescriptorJSONObject(
                from: observation.originatingRequestDescriptor
            ),
            "global_segmentation_mask": pixelBufferObservationJSONObject(from: observation.globalSegmentationMask),
            "top_left": normalizedPointJSONObject(from: observation.topLeft),
            "top_right": normalizedPointJSONObject(from: observation.topRight),
            "bottom_right": normalizedPointJSONObject(from: observation.bottomRight),
            "bottom_left": normalizedPointJSONObject(from: observation.bottomLeft),
        ]
    }

    static func normalizedRegionJSONObject(from contour: ContoursObservation.Contour) -> [String: Any] {
        [
            "aspect_ratio": contour.aspectRatio,
            "index_path": Array(contour.indexPath),
            "point_count": contour.pointCount,
            "normalized_points": contour.normalizedPoints.map(simdPointJSONObject(from:)),
            "child_contours": contour.childContours.map(normalizedRegionJSONObject(from:)),
        ]
    }

    static func requestDescriptorJSONObject(from descriptor: RequestDescriptor?) -> Any {
        guard let descriptor else { return NSNull() }
        return ["identifier": String(describing: descriptor)]
    }

    private static func pixelBufferObservationJSONObject(from observation: PixelBufferObservation) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "originating_request_descriptor": requestDescriptorJSONObject(
                from: observation.originatingRequestDescriptor
            ),
            "size": [
                "width": observation.size.width,
                "height": observation.size.height,
            ],
            "pixel_format": VisionSerialization.fourCCString(from: observation.pixelFormat),
            "pixel_buffer": pixelBufferJSONObject(from: observation),
        ]
    }

    private static func recognizedTextJSONObject(from text: RecognizedText) -> [String: Any] {
        [
            "string": text.string,
            "confidence": text.confidence,
        ]
    }

    private static func normalizedPointJSONObject(from point: NormalizedPoint) -> [String: Any] {
        [
            "x": point.x,
            "y": point.y,
        ]
    }

    private static func simdPointJSONObject(from point: SIMD2<Float>) -> [String: Any] {
        [
            "x": Double(point.x),
            "y": Double(point.y),
        ]
    }

    private static func pixelBufferJSONObject(from observation: PixelBufferObservation) -> Any {
        let width = Int(observation.size.width)
        let height = Int(observation.size.height)
        guard width > 0, height > 0 else { return NSNull() }

        if let cgImage = try? observation.cgImage {
            let bytesPerRow = cgImage.bytesPerRow
            let byteCount = bytesPerRow * height
            guard let dataProvider = cgImage.dataProvider,
                  let cfData = dataProvider.data,
                  let baseAddress = CFDataGetBytePtr(cfData)
            else {
                return NSNull()
            }

            return [
                "width": width,
                "height": height,
                "pixel_format": VisionSerialization.fourCCString(from: observation.pixelFormat),
                "bytes_per_row": bytesPerRow,
                "data": Data(bytes: baseAddress, count: byteCount).base64EncodedString(),
            ]
        }

        let bytesPerPixel = bytesPerPixel(for: observation.pixelFormat)
        guard bytesPerPixel > 0 else { return NSNull() }

        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height
        var data = Data(count: byteCount)
        var copyFailed = false

        observation.withUnsafePointer { pointer in
            data.withUnsafeMutableBytes { destination in
                guard let baseAddress = destination.baseAddress else {
                    copyFailed = true
                    return
                }
                memcpy(baseAddress, pointer, byteCount)
            }
        }

        guard !copyFailed else { return NSNull() }

        return [
            "width": width,
            "height": height,
            "pixel_format": VisionSerialization.fourCCString(from: observation.pixelFormat),
            "bytes_per_row": bytesPerRow,
            "data": data.base64EncodedString(),
        ]
    }

    private static func bytesPerPixel(for pixelFormat: UInt32) -> Int {
        let format = OSType(pixelFormat)
        switch format {
        case kCVPixelFormatType_OneComponent8,
             kCVPixelFormatType_OneComponent16,
             kCVPixelFormatType_OneComponent16Half:
            return (format == kCVPixelFormatType_OneComponent8) ? 1 : 2
        case kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_32ARGB,
             kCVPixelFormatType_32RGBA:
            return 4
        default:
            let fourCC = VisionSerialization.fourCCString(from: pixelFormat)
            if fourCC.hasPrefix("L") || fourCC.hasPrefix("l") {
                if fourCC.contains("8") { return 1 }
                if fourCC.contains("16") { return 2 }
            }
            return 0
        }
    }

    private static func base64DataValue(_ data: Data?) -> Any {
        data?.base64EncodedString() ?? NSNull()
    }

    private static func bcp47String(from language: Locale.Language) -> String {
        var components: [String] = []
        if let languageCode = language.languageCode?.identifier {
            components.append(languageCode)
        }
        if let script = language.script?.identifier {
            components.append(script)
        }
        if let region = language.region?.identifier {
            components.append(region)
        }
        if components.isEmpty {
            return language.minimalIdentifier
        }
        return components.joined(separator: "-")
    }

    private static func textDirectionString(from direction: RecognizedTextObservation.Direction?) -> String? {
        switch direction {
        case .leftToRight: "left_to_right"
        case .rightToLeft: "right_to_left"
        case .topToBottom: "top_to_bottom"
        case nil: nil
        @unknown default: nil
        }
    }

    static func barcodeSymbologyIdentifier(from symbology: BarcodeSymbology) throws -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(symbology)
        } catch {
            throw VisionProviderError.serializationFailed
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let identifier = object.keys.first
        else {
            throw VisionProviderError.serializationFailed
        }
        return identifier
    }

    private static func compositeTypeString(from type: BarcodeObservation.CompositeType?) -> String? {
        switch type {
        case .gs1TypeA: "gs1_type_a"
        case .gs1TypeB: "gs1_type_b"
        case .gs1TypeC: "gs1_type_c"
        case .linked: "linked"
        case nil: nil
        @unknown default: nil
        }
    }
}

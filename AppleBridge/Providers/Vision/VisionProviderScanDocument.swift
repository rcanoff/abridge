import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func scanDocument(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseScanDocumentArguments(payloadJson)
            let result = try store.scanDocument(request: arguments)
            let payloadObject = VisionSerialization.scanDocumentResponseJSONObject(
                observations: result.observations,
                segmentation: result.segmentation,
                maximumCandidateCount: arguments.maximumCandidateCount
            )
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func parseScanDocumentArguments(_ payloadJson: String) throws -> VisionScanDocumentRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw VisionProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let imageData = try requiredImageDataArgument(in: dictionary)
        let orientation = try optionalOrientationArgument(in: dictionary)
        let revision = try optionalDocumentRevisionArgument(in: dictionary)
        let regionOfInterest = try optionalNormalizedRegionOfInterestArgument(in: dictionary)
        let textRecognitionOptions = try optionalTextRecognitionOptionsArgument(in: dictionary)
        let barcodeDetectionOptions = try optionalBarcodeDetectionOptionsArgument(in: dictionary)
        let includeSegmentation = try optionalBoolArgument(in: dictionary, key: "include_segmentation") ?? false
        let maximumCandidateCount = try optionalMaximumCandidateCountArgument(in: dictionary)

        return VisionScanDocumentRequest(
            imageData: imageData,
            orientation: orientation,
            revision: revision,
            regionOfInterest: regionOfInterest,
            textRecognitionOptions: textRecognitionOptions,
            barcodeDetectionOptions: barcodeDetectionOptions,
            includeSegmentation: includeSegmentation,
            maximumCandidateCount: maximumCandidateCount
        )
    }

    private func requiredImageDataArgument(in dictionary: [String: Any]) throws -> Data {
        guard dictionary.keys.contains("image_data") else {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        if dictionary["image_data"] is NSNull {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        guard let encoded = dictionary["image_data"] as? String else {
            throw VisionProviderError.invalidArguments("image_data must be a string")
        }

        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        guard let data = Data(base64Encoded: trimmed) else {
            throw VisionProviderError.invalidArguments("image_data must be valid base64")
        }

        return data
    }

    private func optionalOrientationArgument(in dictionary: [String: Any]) throws -> CGImagePropertyOrientation? {
        guard dictionary.keys.contains("orientation") else { return nil }
        if dictionary["orientation"] is NSNull { return nil }

        let value: UInt32
        switch dictionary["orientation"] {
        case let number as Int:
            guard number >= 1, number <= 8 else {
                throw VisionProviderError.invalidArguments("orientation must be between 1 and 8")
            }
            value = UInt32(number)
        case let number as Double:
            guard number >= 1, number <= 8, number.rounded() == number else {
                throw VisionProviderError.invalidArguments("orientation must be between 1 and 8")
            }
            value = UInt32(number)
        default:
            throw VisionProviderError.invalidArguments("orientation must be an integer between 1 and 8")
        }

        guard let orientation = CGImagePropertyOrientation(rawValue: value) else {
            throw VisionProviderError.invalidArguments("orientation must be between 1 and 8")
        }
        return orientation
    }

    private func optionalDocumentRevisionArgument(
        in dictionary: [String: Any]
    ) throws -> RecognizeDocumentsRequest.Revision? {
        guard dictionary.keys.contains("revision") else { return nil }
        if dictionary["revision"] is NSNull { return nil }

        guard let value = dictionary["revision"] as? String else {
            throw VisionProviderError.invalidArguments("revision must be a string or null")
        }

        switch value {
        case "revision1":
            return .revision1
        default:
            throw VisionProviderError.invalidArguments("revision must be one of: revision1")
        }
    }

    private func optionalNormalizedRegionOfInterestArgument(
        in dictionary: [String: Any]
    ) throws -> NormalizedRect? {
        guard dictionary.keys.contains("region_of_interest") else { return nil }
        if dictionary["region_of_interest"] is NSNull { return nil }

        guard let region = dictionary["region_of_interest"] as? [String: Any] else {
            throw VisionProviderError.invalidArguments("region_of_interest must be an object or null")
        }

        guard let origin = region["origin"] as? [String: Any],
              let size = region["size"] as? [String: Any]
        else {
            throw VisionProviderError.invalidArguments("region_of_interest requires origin and size")
        }

        let originX = try requiredNumber(in: origin, key: "x", label: "region_of_interest.origin.x")
        let originY = try requiredNumber(in: origin, key: "y", label: "region_of_interest.origin.y")
        let width = try requiredNumber(in: size, key: "width", label: "region_of_interest.size.width")
        let height = try requiredNumber(in: size, key: "height", label: "region_of_interest.size.height")

        return NormalizedRect(x: Double(originX), y: Double(originY), width: Double(width), height: Double(height))
    }

    private func optionalTextRecognitionOptionsArgument(
        in dictionary: [String: Any]
    ) throws -> RecognizeDocumentsRequest.TextRecognitionOptions? {
        guard dictionary.keys.contains("text_recognition_options") else { return nil }
        if dictionary["text_recognition_options"] is NSNull { return nil }

        guard let options = dictionary["text_recognition_options"] as? [String: Any] else {
            throw VisionProviderError.invalidArguments("text_recognition_options must be an object or null")
        }

        var visionOptions = options
        visionOptions.removeValue(forKey: "maximum_candidate_count")
        guard !visionOptions.isEmpty else { return nil }

        return try decodeVisionRequestOptions(
            RecognizeDocumentsRequest.TextRecognitionOptions.self,
            from: visionOptions,
            label: "text_recognition_options"
        )
    }

    private func optionalBarcodeDetectionOptionsArgument(
        in dictionary: [String: Any]
    ) throws -> RecognizeDocumentsRequest.BarcodeDetectionOptions? {
        guard dictionary.keys.contains("barcode_detection_options") else { return nil }
        if dictionary["barcode_detection_options"] is NSNull { return nil }

        guard let options = dictionary["barcode_detection_options"] as? [String: Any] else {
            throw VisionProviderError.invalidArguments("barcode_detection_options must be an object or null")
        }

        return try decodeVisionRequestOptions(
            RecognizeDocumentsRequest.BarcodeDetectionOptions.self,
            from: options,
            label: "barcode_detection_options"
        )
    }

    private func optionalBoolArgument(in dictionary: [String: Any], key: String) throws -> Bool? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        guard let value = dictionary[key] as? Bool else {
            throw VisionProviderError.invalidArguments("\(key) must be a boolean or null")
        }
        return value
    }

    private func optionalMaximumCandidateCountArgument(in dictionary: [String: Any]) throws -> Int {
        let textOptions = dictionary["text_recognition_options"] as? [String: Any]
        guard let textOptions, textOptions.keys.contains("maximum_candidate_count") else { return 1 }
        if textOptions["maximum_candidate_count"] is NSNull { return 1 }

        let value: Int
        switch textOptions["maximum_candidate_count"] {
        case let number as Int:
            value = number
        case let number as Double:
            guard number.rounded() == number else {
                throw VisionProviderError.invalidArguments(
                    "text_recognition_options.maximum_candidate_count must be an integer between 1 and 10"
                )
            }
            value = Int(number)
        default:
            throw VisionProviderError.invalidArguments(
                "text_recognition_options.maximum_candidate_count must be an integer between 1 and 10"
            )
        }

        guard (1 ... 10).contains(value) else {
            throw VisionProviderError.invalidArguments(
                "text_recognition_options.maximum_candidate_count must be between 1 and 10"
            )
        }
        return value
    }

    private func requiredNumber(in dictionary: [String: Any], key: String, label: String) throws -> CGFloat {
        switch dictionary[key] {
        case let value as Double:
            return CGFloat(value)
        case let value as Int:
            return CGFloat(value)
        default:
            throw VisionProviderError.invalidArguments("\(label) must be a number")
        }
    }

    private func decodeVisionRequestOptions<T: Decodable>(
        _ type: T.Type,
        from dictionary: [String: Any],
        label: String
    ) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw VisionProviderError.invalidArguments("\(label) is invalid: \(error.localizedDescription)")
        }
    }
}

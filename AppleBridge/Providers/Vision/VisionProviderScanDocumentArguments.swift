// swiftlint:disable file_length
import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func parseScanDocumentArguments(_ payloadJson: String) throws -> VisionScanDocumentRequest {
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

        let originX = try requiredDouble(in: origin, key: "x", label: "region_of_interest.origin.x")
        let originY = try requiredDouble(in: origin, key: "y", label: "region_of_interest.origin.y")
        let width = try requiredDouble(in: size, key: "width", label: "region_of_interest.size.width")
        let height = try requiredDouble(in: size, key: "height", label: "region_of_interest.size.height")

        return try validatedNormalizedRect(originX: originX, originY: originY, width: width, height: height)
    }

    private func validatedNormalizedRect(
        originX: Double,
        originY: Double,
        width: Double,
        height: Double
    ) throws -> NormalizedRect {
        guard (0 ... 1).contains(originX), (0 ... 1).contains(originY) else {
            throw VisionProviderError.invalidArguments("region_of_interest origin x and y must be between 0 and 1")
        }
        guard width > 0, width <= 1, height > 0, height <= 1 else {
            throw VisionProviderError.invalidArguments(
                "region_of_interest size width and height must be greater than 0 and at most 1"
            )
        }
        guard originX + width <= 1, originY + height <= 1 else {
            throw VisionProviderError.invalidArguments(
                "region_of_interest must fit within the normalized coordinate space"
            )
        }
        return NormalizedRect(x: originX, y: originY, width: width, height: height)
    }

    private func optionalTextRecognitionOptionsArgument(
        in dictionary: [String: Any]
    ) throws -> RecognizeDocumentsRequest.TextRecognitionOptions? {
        guard dictionary.keys.contains("text_recognition_options") else { return nil }
        if dictionary["text_recognition_options"] is NSNull { return nil }

        guard let options = dictionary["text_recognition_options"] as? [String: Any] else {
            throw VisionProviderError.invalidArguments("text_recognition_options must be an object or null")
        }

        var payload = try defaultTextRecognitionOptionsPayload()
        var hasOverride = false

        if let minimumTextHeightFraction = try optionalNonNegativeDoubleArgument(
            in: options,
            key: "minimum_text_height_fraction",
            label: "text_recognition_options.minimum_text_height_fraction"
        ) {
            payload["minimumTextHeightFraction"] = minimumTextHeightFraction
            hasOverride = true
        }
        if let automaticallyDetectLanguage = try optionalBoolArgument(
            in: options,
            key: "automatically_detect_language"
        ) {
            payload["automaticallyDetectLanguage"] = automaticallyDetectLanguage
            hasOverride = true
        }
        if let recognitionLanguages = try optionalRecognitionLanguagesPayload(in: options) {
            payload["recognitionLanguages"] = recognitionLanguages
            hasOverride = true
        }
        if let useLanguageCorrection = try optionalBoolArgument(in: options, key: "use_language_correction") {
            payload["useLanguageCorrection"] = useLanguageCorrection
            hasOverride = true
        }
        if let customWords = try optionalStringArrayArgument(in: options, key: "custom_words") {
            payload["customWords"] = customWords
            hasOverride = true
        }

        guard hasOverride else { return nil }
        return try decodeVisionRequestOptions(
            RecognizeDocumentsRequest.TextRecognitionOptions.self,
            from: payload,
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

        var payload = try defaultBarcodeDetectionOptionsPayload()
        var hasOverride = false

        if let enabled = try optionalBoolArgument(in: options, key: "enabled") {
            payload["enabled"] = enabled
            hasOverride = true
        }
        if let symbologies = try optionalStringArrayArgument(in: options, key: "symbologies") {
            payload["symbologies"] = symbologies.map { [$0: [:]] as [String: [String: String]] }
            hasOverride = true
        }
        if let coalesceCompositeSymbologies = try optionalBoolArgument(
            in: options,
            key: "coalesce_composite_symbologies"
        ) {
            payload["coalesceCompositeSymbologies"] = coalesceCompositeSymbologies
            hasOverride = true
        }

        guard hasOverride else { return nil }
        return try decodeVisionRequestOptions(
            RecognizeDocumentsRequest.BarcodeDetectionOptions.self,
            from: payload,
            label: "barcode_detection_options"
        )
    }

    private func defaultBarcodeDetectionOptionsPayload() throws -> [String: Any] {
        let request = RecognizeDocumentsRequest()
        let data = try JSONEncoder().encode(request.barcodeDetectionOptions)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VisionProviderError.invalidArguments("barcode_detection_options is invalid")
        }
        return payload
    }

    private func defaultTextRecognitionOptionsPayload() throws -> [String: Any] {
        let request = RecognizeDocumentsRequest()
        let data = try JSONEncoder().encode(request.textRecognitionOptions)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VisionProviderError.invalidArguments("text_recognition_options is invalid")
        }
        return payload
    }

    private func optionalRecognitionLanguagesPayload(in dictionary: [String: Any]) throws -> [[String: Any]]? {
        guard let languageTags = try optionalNonEmptyStringArrayArgument(
            in: dictionary,
            key: "recognition_languages",
            label: "text_recognition_options.recognition_languages"
        ) else {
            return nil
        }

        return try languageTags.map { tag in
            let components = tag.split(separator: "-", maxSplits: 1).map(String.init)
            guard let languageCode = components.first, !languageCode.isEmpty else {
                throw VisionProviderError.invalidArguments(
                    "text_recognition_options.recognition_languages items must be non-empty strings"
                )
            }
            var languageComponents: [String: String] = ["languageCode": languageCode]
            if components.count == 2 {
                languageComponents["region"] = components[1]
            }
            return ["components": languageComponents]
        }
    }

    private func optionalNonNegativeDoubleArgument(
        in dictionary: [String: Any],
        key: String,
        label: String
    ) throws -> Double? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        let value: Double
        switch dictionary[key] {
        case let number as Double:
            value = number
        case let number as Int:
            value = Double(number)
        default:
            throw VisionProviderError.invalidArguments("\(label) must be a number or null")
        }

        guard value >= 0 else {
            throw VisionProviderError.invalidArguments("\(label) must be greater than or equal to 0")
        }
        return value
    }

    private func optionalStringArrayArgument(
        in dictionary: [String: Any],
        key: String
    ) throws -> [String]? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        guard let values = dictionary[key] as? [Any] else {
            throw VisionProviderError.invalidArguments("\(key) must be an array or null")
        }

        var strings: [String] = []
        strings.reserveCapacity(values.count)
        for value in values {
            guard let string = value as? String else {
                throw VisionProviderError.invalidArguments("\(key) items must be strings")
            }
            strings.append(string)
        }
        return strings
    }

    private func optionalNonEmptyStringArrayArgument(
        in dictionary: [String: Any],
        key: String,
        label: String
    ) throws -> [String]? {
        guard let strings = try optionalStringArrayArgument(in: dictionary, key: key) else {
            return nil
        }

        for string in strings where string.isEmpty {
            throw VisionProviderError.invalidArguments("\(label) items must be non-empty strings")
        }
        return strings
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

    private func requiredDouble(in dictionary: [String: Any], key: String, label: String) throws -> Double {
        switch dictionary[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
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
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VisionProviderError.invalidArguments("\(label) is invalid: \(error.localizedDescription)")
        }
    }
}

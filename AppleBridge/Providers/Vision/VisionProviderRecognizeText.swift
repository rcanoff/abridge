import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func recognizeText(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseRecognizeTextArguments(payloadJson)
            let observations = try store.recognizeText(request: arguments)
            let payloadObject = VisionSerialization.recognizeTextResponseJSONObject(
                observations: observations,
                maxCandidateCount: arguments.maxCandidateCount
            )
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func parseRecognizeTextArguments(_ payloadJson: String) throws -> VisionRecognizeTextRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw VisionProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let imageData = try requiredImageDataArgument(in: dictionary)
        let orientation = try optionalOrientationArgument(in: dictionary)
        let recognitionLanguages = try optionalStringArrayArgument(in: dictionary, key: "recognition_languages")
        let customWords = try optionalStringArrayArgument(in: dictionary, key: "custom_words")
        let recognitionLevel = try optionalRecognitionLevelArgument(in: dictionary)
        let usesLanguageCorrection = try optionalBoolArgument(in: dictionary, key: "uses_language_correction")
        let automaticallyDetectsLanguage = try optionalBoolArgument(
            in: dictionary,
            key: "automatically_detects_language"
        )
        let minimumTextHeight = try optionalFloatArgument(in: dictionary, key: "minimum_text_height")
        let revision = try optionalIntArgument(in: dictionary, key: "revision")
        let preferBackgroundProcessing = try optionalBoolArgument(
            in: dictionary,
            key: "prefer_background_processing"
        )
        let regionOfInterest = try optionalRegionOfInterestArgument(in: dictionary)
        let maxCandidateCount = try optionalMaxCandidateCountArgument(in: dictionary)

        return VisionRecognizeTextRequest(
            imageData: imageData,
            orientation: orientation,
            recognitionLanguages: recognitionLanguages,
            customWords: customWords,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            automaticallyDetectsLanguage: automaticallyDetectsLanguage,
            minimumTextHeight: minimumTextHeight,
            revision: revision,
            preferBackgroundProcessing: preferBackgroundProcessing,
            regionOfInterest: regionOfInterest,
            maxCandidateCount: maxCandidateCount
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

    private func optionalRecognitionLevelArgument(
        in dictionary: [String: Any]
    ) throws -> VNRequestTextRecognitionLevel {
        guard dictionary.keys.contains("recognition_level") else { return .accurate }
        if dictionary["recognition_level"] is NSNull { return .accurate }

        guard let value = dictionary["recognition_level"] as? String else {
            throw VisionProviderError.invalidArguments("recognition_level must be a string or null")
        }

        switch value {
        case "accurate":
            return .accurate
        case "fast":
            return .fast
        default:
            throw VisionProviderError.invalidArguments("recognition_level must be one of: accurate, fast")
        }
    }

    private func optionalBoolArgument(in dictionary: [String: Any], key: String) throws -> Bool? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        guard let value = dictionary[key] as? Bool else {
            throw VisionProviderError.invalidArguments("\(key) must be a boolean or null")
        }
        return value
    }

    private func optionalFloatArgument(in dictionary: [String: Any], key: String) throws -> Float? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        switch dictionary[key] {
        case let value as Double:
            guard value >= 0 else {
                throw VisionProviderError.invalidArguments("\(key) must be greater than or equal to 0")
            }
            return Float(value)
        case let value as Int:
            guard value >= 0 else {
                throw VisionProviderError.invalidArguments("\(key) must be greater than or equal to 0")
            }
            return Float(value)
        default:
            throw VisionProviderError.invalidArguments("\(key) must be a number or null")
        }
    }

    private func optionalIntArgument(in dictionary: [String: Any], key: String) throws -> Int? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        switch dictionary[key] {
        case let value as Int:
            guard value >= 0 else {
                throw VisionProviderError.invalidArguments("\(key) must be a non-negative integer")
            }
            return value
        case let value as Double:
            guard value >= 0, value.rounded() == value else {
                throw VisionProviderError.invalidArguments("\(key) must be a non-negative integer")
            }
            return Int(value)
        default:
            throw VisionProviderError.invalidArguments("\(key) must be an integer or null")
        }
    }

    private func optionalRegionOfInterestArgument(in dictionary: [String: Any]) throws -> CGRect? {
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

        let x = try requiredNumber(in: origin, key: "x", label: "region_of_interest.origin.x")
        let y = try requiredNumber(in: origin, key: "y", label: "region_of_interest.origin.y")
        let width = try requiredNumber(in: size, key: "width", label: "region_of_interest.size.width")
        let height = try requiredNumber(in: size, key: "height", label: "region_of_interest.size.height")

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func optionalMaxCandidateCountArgument(in dictionary: [String: Any]) throws -> Int {
        guard dictionary.keys.contains("max_candidate_count") else { return 1 }
        if dictionary["max_candidate_count"] is NSNull { return 1 }

        let value: Int
        switch dictionary["max_candidate_count"] {
        case let number as Int:
            value = number
        case let number as Double:
            guard number.rounded() == number else {
                throw VisionProviderError.invalidArguments("max_candidate_count must be an integer between 1 and 10")
            }
            value = Int(number)
        default:
            throw VisionProviderError.invalidArguments("max_candidate_count must be an integer between 1 and 10")
        }

        guard (1 ... 10).contains(value) else {
            throw VisionProviderError.invalidArguments("max_candidate_count must be between 1 and 10")
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
}
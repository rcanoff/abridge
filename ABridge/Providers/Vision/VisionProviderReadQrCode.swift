import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func readQrCode(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseReadQrCodeArguments(payloadJson)
            let observations = try store.readQrCode(request: arguments)
            let payloadObject = VisionSerialization.readQrCodeResponseJSONObject(observations: observations)
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func parseReadQrCodeArguments(_ payloadJson: String) throws -> VisionReadQrCodeRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw VisionProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let imageData = try requiredImageDataArgument(in: dictionary)
        let orientation = try optionalOrientationArgument(in: dictionary)
        let revision = try optionalIntArgument(in: dictionary, key: "revision")
        let regionOfInterest = try optionalRegionOfInterestArgument(in: dictionary)
        let coalesceCompositeSymbologies = try optionalBoolArgument(
            in: dictionary,
            key: "coalesce_composite_symbologies"
        )

        return VisionReadQrCodeRequest(
            imageData: imageData,
            orientation: orientation,
            revision: revision,
            regionOfInterest: regionOfInterest,
            coalesceCompositeSymbologies: coalesceCompositeSymbologies
        )
    }

    private func requiredImageDataArgument(in dictionary: [String: Any]) throws -> Data {
        // Required non-empty image_data string is schema-owned; base64 decode is runtime.
        let trimmed = SchemaTrustedPayload.requiredString(dictionary, "image_data")
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

    private func optionalBoolArgument(in dictionary: [String: Any], key: String) throws -> Bool? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull { return nil }

        guard let value = dictionary[key] as? Bool else {
            throw VisionProviderError.invalidArguments("\(key) must be a boolean or null")
        }
        return value
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

        let originX = try requiredNumber(in: origin, key: "x", label: "region_of_interest.origin.x")
        let originY = try requiredNumber(in: origin, key: "y", label: "region_of_interest.origin.y")
        let width = try requiredNumber(in: size, key: "width", label: "region_of_interest.size.width")
        let height = try requiredNumber(in: size, key: "height", label: "region_of_interest.size.height")

        return CGRect(x: originX, y: originY, width: width, height: height)
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

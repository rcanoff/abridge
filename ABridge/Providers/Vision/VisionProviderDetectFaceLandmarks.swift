import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func detectFaceLandmarks(payloadJson: String) async -> ProviderResponse {
        do {
            let arguments = try parseDetectFaceLandmarksArguments(payloadJson)
            let observations = try await store.detectFaceLandmarks(request: arguments)
            let payloadObject = VisionSerialization.detectFaceLandmarksResponseJSONObject(observations: observations)
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func parseDetectFaceLandmarksArguments(_ payloadJson: String) throws -> VisionDetectFaceLandmarksRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw VisionProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let imageData = try requiredImageDataArgument(in: dictionary)
        let orientation = try optionalOrientationArgument(in: dictionary)
        let revision = try optionalFaceLandmarksRevisionArgument(in: dictionary)
        let regionOfInterest = try optionalNormalizedRegionOfInterestArgument(in: dictionary)
        let constellation = try optionalConstellationArgument(in: dictionary)

        return VisionDetectFaceLandmarksRequest(
            imageData: imageData,
            orientation: orientation,
            revision: revision,
            regionOfInterest: regionOfInterest,
            constellation: constellation
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
        if dictionary["orientation"] is NSNull {
            return nil
        }

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

    private func optionalIntArgument(in dictionary: [String: Any], key: String) throws -> Int? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull {
            return nil
        }

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

    private func optionalFaceLandmarksRevisionArgument(in dictionary: [String: Any]) throws -> Int? {
        guard let revision = try optionalIntArgument(in: dictionary, key: "revision") else {
            return nil
        }

        let supportedRevisions = VNDetectFaceLandmarksRequest.supportedRevisions
        guard supportedRevisions.contains(revision) else {
            throw VisionProviderError.invalidArguments(
                "revision must be one of the supported face landmark detection revisions"
            )
        }

        return revision
    }

    private func optionalNormalizedRegionOfInterestArgument(in dictionary: [String: Any]) throws -> CGRect? {
        guard dictionary.keys.contains("region_of_interest") else { return nil }
        if dictionary["region_of_interest"] is NSNull {
            return nil
        }

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

        return try normalizedRegionOfInterest(
            originX: originX,
            originY: originY,
            width: width,
            height: height
        )
    }

    private func normalizedRegionOfInterest(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) throws -> CGRect {
        guard originX >= 0, originY >= 0 else {
            throw VisionProviderError.invalidArguments("region_of_interest origin must be non-negative")
        }
        guard width > 0, height > 0 else {
            throw VisionProviderError.invalidArguments("region_of_interest size must be positive")
        }
        guard originX <= 1, originY <= 1, width <= 1, height <= 1 else {
            throw VisionProviderError.invalidArguments(
                "region_of_interest must use normalized unit coordinates between 0 and 1"
            )
        }
        guard originX + width <= 1, originY + height <= 1 else {
            throw VisionProviderError.invalidArguments(
                "region_of_interest must fit within normalized unit coordinates"
            )
        }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func optionalConstellationArgument(
        in dictionary: [String: Any]
    ) throws -> VNRequestFaceLandmarksConstellation {
        guard dictionary.keys.contains("constellation") else { return .constellationNotDefined }
        if dictionary["constellation"] is NSNull {
            return .constellationNotDefined
        }

        guard let value = dictionary["constellation"] as? String else {
            throw VisionProviderError.invalidArguments("constellation must be a string or null")
        }

        switch value {
        case "not_defined":
            return .constellationNotDefined
        case "65_points":
            return .constellation65Points
        case "76_points":
            return .constellation76Points
        default:
            throw VisionProviderError.invalidArguments(
                "constellation must be one of: not_defined, 65_points, 76_points"
            )
        }
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

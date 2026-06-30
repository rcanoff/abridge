import CoreGraphics
import Foundation
import Vision

extension VisionProvider {
    func detectBarcodes(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseDetectBarcodesArguments(payloadJson)
            let observations = try store.detectBarcodes(request: arguments)
            let payloadObject = VisionBarcodeSerialization.detectBarcodesResponseJSONObject(observations: observations)
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func parseDetectBarcodesArguments(_ payloadJson: String) throws -> VisionDetectBarcodesRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionProviderError.invalidArguments("image_data is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw VisionProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let imageData = try requiredImageDataArgument(in: dictionary)
        let orientation = try optionalOrientationArgument(in: dictionary)
        let revision = try optionalBarcodeRevisionArgument(in: dictionary)
        let regionOfInterest = try optionalNormalizedRegionOfInterestArgument(in: dictionary)
        let symbologies = try optionalSymbologiesArgument(in: dictionary)
        let coalesceCompositeSymbologies = try optionalBoolArgument(
            in: dictionary,
            key: "coalesce_composite_symbologies"
        )

        return VisionDetectBarcodesRequest(
            imageData: imageData,
            orientation: orientation,
            revision: revision,
            regionOfInterest: regionOfInterest,
            symbologies: symbologies,
            coalesceCompositeSymbologies: coalesceCompositeSymbologies
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

    private func optionalBarcodeRevisionArgument(
        in dictionary: [String: Any]
    ) throws -> DetectBarcodesRequest.Revision? {
        guard dictionary.keys.contains("revision") else { return nil }
        if dictionary["revision"] is NSNull { return nil }

        guard let value = dictionary["revision"] as? String else {
            throw VisionProviderError.invalidArguments("revision must be a string or null")
        }

        switch value {
        case "revision1":
            return nil
        case "revision4":
            return .revision4
        default:
            throw VisionProviderError.invalidArguments("revision must be one of: revision1, revision4")
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

    private func optionalSymbologiesArgument(in dictionary: [String: Any]) throws -> [BarcodeSymbology]? {
        guard dictionary.keys.contains("symbologies") else { return nil }
        if dictionary["symbologies"] is NSNull { return nil }

        guard let values = dictionary["symbologies"] as? [Any] else {
            throw VisionProviderError.invalidArguments("symbologies must be an array or null")
        }

        var symbologies: [BarcodeSymbology] = []
        symbologies.reserveCapacity(values.count)

        for value in values {
            guard let rawValue = value as? String else {
                throw VisionProviderError.invalidArguments("symbologies must contain strings")
            }
            try symbologies.append(decodeBarcodeSymbology(from: rawValue))
        }

        return symbologies
    }

    private func decodeBarcodeSymbology(from rawValue: String) throws -> BarcodeSymbology {
        let wrapper: [String: [String: String]] = [rawValue: [:]]
        let data = try JSONSerialization.data(withJSONObject: wrapper)
        do {
            return try JSONDecoder().decode(BarcodeSymbology.self, from: data)
        } catch {
            throw VisionProviderError.invalidArguments("symbologies contains unknown symbology: \(rawValue)")
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

import CoreGraphics
import Foundation

extension EventKitDeserialization {
    static func optionalPresentCGColor(_ dictionary: [String: Any], key: String) throws -> OptionalField<CGColor> {
        guard dictionary.keys.contains(key) else { return .absent }
        return try .present(cgColor(from: dictionary[key]))
    }

    static func cgColor(from value: Any?) throws -> CGColor? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("cg_color must be an object or null")
        }

        guard let components = try cgColorComponents(from: dictionary["components"]) else {
            throw EventKitProviderError.invalidArguments("cg_color components are required")
        }

        let alpha = try cgColorAlpha(from: dictionary["alpha"], components: components)
        let colorSpaceModel = try cgColorSpaceModel(from: dictionary)
        if let colorSpaceModel {
            try validateComponentCount(components.count, for: colorSpaceModel)
        }

        let colorSpace = try cgColorSpace(from: colorSpaceModel)
        if let colorSpace {
            let normalized = normalizedComponents(components, alpha: alpha, colorSpaceModel: colorSpaceModel)
            guard let color = CGColor(colorSpace: colorSpace, components: normalized) else {
                throw EventKitProviderError.invalidArguments("cg_color is invalid for the given color_space_model")
            }
            return color
        }

        guard !components.isEmpty else {
            throw EventKitProviderError.invalidArguments("cg_color components are required")
        }

        return CGColor(
            red: components[0],
            green: components.count > 1 ? components[1] : components[0],
            blue: components.count > 2 ? components[2] : components[0],
            alpha: alpha
        )
    }

    private static func cgColorComponents(from value: Any?) throws -> [CGFloat]? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let array = value as? [Any], !array.isEmpty else {
            throw EventKitProviderError.invalidArguments("cg_color components must be a non-empty array")
        }

        var components: [CGFloat] = []
        components.reserveCapacity(array.count)
        for element in array {
            if let number = element as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    throw EventKitProviderError.invalidArguments("cg_color components must be numbers")
                }
                components.append(CGFloat(number.doubleValue))
            } else if let double = element as? Double {
                components.append(CGFloat(double))
            } else if let float = element as? CGFloat {
                components.append(float)
            } else if let int = element as? Int {
                components.append(CGFloat(int))
            } else {
                throw EventKitProviderError.invalidArguments("cg_color components must be numbers")
            }
        }
        return components
    }

    private static func cgColorAlpha(from value: Any?, components: [CGFloat]) throws -> CGFloat {
        guard let value else {
            return components.count > 3 ? components[3] : 1
        }
        if value is NSNull {
            return components.count > 3 ? components[3] : 1
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw EventKitProviderError.invalidArguments("cg_color alpha must be a number or null")
            }
            return CGFloat(number.doubleValue)
        }
        if value is Bool {
            throw EventKitProviderError.invalidArguments("cg_color alpha must be a number or null")
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let float = value as? CGFloat {
            return float
        }
        if let int = value as? Int {
            return CGFloat(int)
        }
        throw EventKitProviderError.invalidArguments("cg_color alpha must be a number or null")
    }

    private static func cgColorSpaceModel(from dictionary: [String: Any]) throws -> String? {
        guard let modelValue = dictionary["color_space_model"] else { return nil }
        if modelValue is NSNull {
            return nil
        }
        guard let model = modelValue as? String else {
            throw EventKitProviderError.invalidArguments("cg_color color_space_model must be a string or null")
        }
        return model
    }

    private static func cgColorSpace(from model: String?) throws -> CGColorSpace? {
        guard let model else { return nil }

        switch model {
        case "rgb":
            return CGColorSpace(name: CGColorSpace.sRGB)
        case "gray":
            return CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        case "cmyk":
            return CGColorSpace(name: CGColorSpace.genericCMYK)
        default:
            throw EventKitProviderError.invalidArguments("cg_color color_space_model is not supported")
        }
    }

    private static func validateComponentCount(_ count: Int, for model: String) throws {
        switch model {
        case "rgb":
            guard count == 3 || count == 4 else {
                throw EventKitProviderError.invalidArguments(
                    "cg_color components for rgb must have 3 or 4 values"
                )
            }
        case "gray":
            guard count == 1 || count == 2 else {
                throw EventKitProviderError.invalidArguments(
                    "cg_color components for gray must have 1 or 2 values"
                )
            }
        case "cmyk":
            guard count == 4 || count == 5 else {
                throw EventKitProviderError.invalidArguments(
                    "cg_color components for cmyk must have 4 or 5 values"
                )
            }
        default:
            break
        }
    }

    private static func normalizedComponents(
        _ components: [CGFloat],
        alpha: CGFloat,
        colorSpaceModel: String?
    ) -> [CGFloat] {
        switch colorSpaceModel {
        case "rgb":
            switch components.count {
            case 3:
                [components[0], components[1], components[2], alpha]
            default:
                components
            }
        case "gray":
            switch components.count {
            case 1:
                [components[0], alpha]
            default:
                components
            }
        default:
            components
        }
    }
}

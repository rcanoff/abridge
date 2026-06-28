import CoreGraphics
import Foundation

extension EventKitDeserialization {
    static func cgColor(from value: Any?) throws -> CGColor? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("cg_color must be an object or null")
        }

        guard let components = try cgColorComponents(from: dictionary["components"]) else {
            throw EventKitProviderError.invalidArguments("cg_color components are required")
        }

        let alpha = try cgColorAlpha(from: dictionary["alpha"], components: components)
        let colorSpace = try cgColorSpace(from: dictionary)

        if let colorSpace {
            return CGColor(colorSpace: colorSpace, components: normalizedComponents(components, alpha: alpha))
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
        if value is NSNull { return nil }
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

    private static func cgColorSpace(from dictionary: [String: Any]) throws -> CGColorSpace? {
        guard let modelValue = dictionary["color_space_model"] else { return nil }
        if modelValue is NSNull { return nil }
        guard let model = modelValue as? String else {
            throw EventKitProviderError.invalidArguments("cg_color color_space_model must be a string or null")
        }

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

    private static func normalizedComponents(_ components: [CGFloat], alpha: CGFloat) -> [CGFloat] {
        switch components.count {
        case 1:
            [components[0], alpha]
        case 3:
            [components[0], components[1], components[2], alpha]
        default:
            components
        }
    }
}

import Foundation

extension VisionProvider {
    func optionalNonNegativeDoubleArgument(
        in dictionary: [String: Any],
        key: String,
        label: String
    ) throws -> Double? {
        guard dictionary.keys.contains(key) else { return nil }
        if dictionary[key] is NSNull {
            return nil
        }

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

    func optionalMaximumCandidateCountArgument(in dictionary: [String: Any]) throws -> Int {
        let textOptions = dictionary["text_recognition_options"] as? [String: Any]
        guard let textOptions, textOptions.keys.contains("maximum_candidate_count") else { return 1 }
        if textOptions["maximum_candidate_count"] is NSNull {
            return 1
        }

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

    func requiredDouble(in dictionary: [String: Any], key: String, label: String) throws -> Double {
        switch dictionary[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        default:
            throw VisionProviderError.invalidArguments("\(label) must be a number")
        }
    }

    func decodeVisionRequestOptions<T: Decodable>(
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

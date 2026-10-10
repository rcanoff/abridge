import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func searchPlaces(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseSearchPlacesArguments(payloadJson)
            let result = try store.searchPlaces(request: arguments)
            let payloadObject = MapKitSerialization.searchResponseJSONObject(
                mapItems: result.mapItems,
                boundingRegion: result.boundingRegion
            )
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseSearchPlacesArguments(_ payloadJson: String) throws -> MapKitSearchRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let query = try requiredQueryArgument(in: dictionary)
        let region = try optionalRegionArgument(in: dictionary)
        let regionPriority = try optionalRegionPriorityArgument(in: dictionary)
        let resultTypes = try optionalResultTypesArgument(in: dictionary)

        return MapKitSearchRequest(
            query: query,
            region: region,
            regionPriority: regionPriority,
            resultTypes: resultTypes
        )
    }

    private func requiredQueryArgument(in dictionary: [String: Any]) throws -> String {
        // Required non-empty query is schema-owned (Rust).
        SchemaTrustedPayload.requiredString(dictionary, "query")
    }

    private func optionalRegionPriorityArgument(
        in dictionary: [String: Any]
    ) throws -> MKLocalSearchRegionPriority {
        guard dictionary.keys.contains("region_priority") else {
            return .default
        }

        if dictionary["region_priority"] is NSNull {
            return .default
        }

        guard let value = dictionary["region_priority"] as? String else {
            throw MapKitProviderError.invalidArguments("region_priority must be a string or null")
        }

        switch value {
        case "default":
            return .default
        case "required":
            return .required
        default:
            throw MapKitProviderError.invalidArguments(
                "region_priority must be one of: default, required"
            )
        }
    }

    private func optionalResultTypesArgument(
        in dictionary: [String: Any]
    ) throws -> MKLocalSearch.ResultType? {
        guard dictionary.keys.contains("result_types") else {
            return nil
        }

        if dictionary["result_types"] is NSNull {
            return nil
        }

        guard let values = dictionary["result_types"] as? [Any] else {
            throw MapKitProviderError.invalidArguments("result_types must be an array or null")
        }

        var resultTypes = MKLocalSearch.ResultType()
        for value in values {
            guard let rawValue = value as? String else {
                throw MapKitProviderError.invalidArguments("result_types items must be strings")
            }

            switch rawValue {
            case "address":
                resultTypes.insert(.address)
            case "point_of_interest":
                resultTypes.insert(.pointOfInterest)
            case "physical_feature":
                resultTypes.insert(.physicalFeature)
            case "query", "physical_feature_query":
                throw MapKitProviderError.invalidArguments(
                    "result_types value \(rawValue) is not supported on this macOS version"
                )
            default:
                throw MapKitProviderError.invalidArguments(
                    "result_types value \(rawValue) is not recognized"
                )
            }
        }

        return resultTypes
    }
}

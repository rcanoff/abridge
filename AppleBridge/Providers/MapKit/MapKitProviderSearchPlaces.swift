import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func searchPlaces(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

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
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapKitProviderError.invalidArguments("query is required")
        }

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
        guard dictionary.keys.contains("query") else {
            throw MapKitProviderError.invalidArguments("query is required")
        }

        if dictionary["query"] is NSNull {
            throw MapKitProviderError.invalidArguments("query is required")
        }

        guard let query = dictionary["query"] as? String else {
            throw MapKitProviderError.invalidArguments("query must be a string")
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("query must not be empty")
        }

        return trimmed
    }

    private func optionalRegionArgument(in dictionary: [String: Any]) throws -> MKCoordinateRegion? {
        guard dictionary.keys.contains("region") else {
            return nil
        }

        if dictionary["region"] is NSNull {
            return nil
        }

        guard let regionDictionary = dictionary["region"] as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("region must be an object or null")
        }

        guard let centerDictionary = regionDictionary["center"] as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("region.center is required")
        }
        guard let spanDictionary = regionDictionary["span"] as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("region.span is required")
        }

        let latitude = try requiredCoordinateComponent(
            named: "latitude",
            in: centerDictionary,
            minimum: -90,
            maximum: 90
        )
        let longitude = try requiredCoordinateComponent(
            named: "longitude",
            in: centerDictionary,
            minimum: -180,
            maximum: 180
        )
        let latitudeDelta = try requiredPositiveSpanComponent(
            named: "latitude_delta",
            in: spanDictionary
        )
        let longitudeDelta = try requiredPositiveSpanComponent(
            named: "longitude_delta",
            in: spanDictionary
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func requiredCoordinateComponent(
        named key: String,
        in dictionary: [String: Any],
        minimum: Double,
        maximum: Double
    ) throws -> Double {
        guard let value = dictionary[key] as? Double else {
            throw MapKitProviderError.invalidArguments("region.center.\(key) must be a number")
        }
        guard value >= minimum, value <= maximum else {
            throw MapKitProviderError.invalidArguments(
                "region.center.\(key) must be between \(minimum) and \(maximum)"
            )
        }
        return value
    }

    private func requiredPositiveSpanComponent(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> Double {
        guard let value = dictionary[key] as? Double else {
            throw MapKitProviderError.invalidArguments("region.span.\(key) must be a number")
        }
        guard value > 0 else {
            throw MapKitProviderError.invalidArguments("region.span.\(key) must be greater than 0")
        }
        return value
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

import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func estimateTravelTime(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseEstimateTravelTimeArguments(payloadJson)
            let result = try store.estimateTravelTime(request: arguments)
            let payloadObject = MapKitSerialization.estimateTravelTimeResponseJSONObject(result: result)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseEstimateTravelTimeArguments(_ payloadJson: String) throws -> MapKitEstimateTravelTimeRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let source = try requiredRouteEndpointArgument(named: "source", in: dictionary)
        let destination = try requiredRouteEndpointArgument(named: "destination", in: dictionary)
        let transportType = try optionalTransportTypeArgument(in: dictionary)
        let departureDate = try optionalISO8601DateArgument(named: "departure_date", in: dictionary)
        let arrivalDate = try optionalISO8601DateArgument(named: "arrival_date", in: dictionary)

        if departureDate != nil, arrivalDate != nil {
            throw MapKitProviderError.invalidArguments("provide departure_date or arrival_date, not both")
        }

        return MapKitEstimateTravelTimeRequest(
            source: source,
            destination: destination,
            transportType: transportType,
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
    }

    private func requiredRouteEndpointArgument(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> MapKitRouteEndpoint {
        guard let endpointDictionary = dictionary[key] as? [String: Any] else {
            // Schema requires object; mapping fails if wrong type/absent offline.
            throw MapKitProviderError.invalidArguments("\(key) must be an object")
        }

        let coordinate = try requiredNestedCoordinateArgument(
            in: endpointDictionary,
            prefix: "\(key).coordinate"
        )
        return MapKitRouteEndpoint(coordinate: coordinate)
    }

    private func requiredNestedCoordinateArgument(
        in dictionary: [String: Any],
        prefix: String
    ) throws -> CLLocationCoordinate2D {
        guard let coordinateDictionary = dictionary["coordinate"] as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("\(prefix) must be an object")
        }

        let latitude = try requiredCoordinateComponent(
            named: "latitude",
            in: coordinateDictionary,
            minimum: -90,
            maximum: 90,
            prefix: prefix
        )
        let longitude = try requiredCoordinateComponent(
            named: "longitude",
            in: coordinateDictionary,
            minimum: -180,
            maximum: 180,
            prefix: prefix
        )

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func optionalTransportTypeArgument(in dictionary: [String: Any]) throws -> MKDirectionsTransportType {
        guard dictionary.keys.contains("transport_type") else {
            return .automobile
        }

        if dictionary["transport_type"] is NSNull {
            return .automobile
        }

        guard let rawValue = dictionary["transport_type"] as? String else {
            throw MapKitProviderError.invalidArguments("transport_type must be a string or null")
        }

        switch rawValue {
        case "automobile":
            return .automobile
        case "walking":
            return .walking
        case "transit":
            return .transit
        case "cycling":
            return .cycling
        case "any":
            return .any
        default:
            throw MapKitProviderError.invalidArguments(
                "transport_type must be one of: automobile, walking, transit, cycling, any"
            )
        }
    }

    private func optionalISO8601DateArgument(named key: String, in dictionary: [String: Any]) throws -> Date? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw MapKitProviderError.invalidArguments("\(key) must be an ISO8601 string or null")
        }

        guard let date = Self.parseISO8601Date(value) else {
            throw MapKitProviderError.invalidArguments("\(key) must be a valid ISO8601 date-time")
        }

        return date
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }

        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        return internetDateTime.date(from: value)
    }
}

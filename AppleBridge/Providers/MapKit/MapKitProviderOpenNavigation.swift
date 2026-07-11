import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func openNavigation(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseOpenNavigationArguments(payloadJson)
            let result = try store.openNavigation(request: arguments)
            let payloadObject = MapKitSerialization.openNavigationResponseJSONObject(result: result)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseOpenNavigationArguments(_ payloadJson: String) throws -> MapKitOpenNavigationRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let source = try requiredRouteEndpointArgument(named: "source", in: dictionary)
        let destination = try requiredRouteEndpointArgument(named: "destination", in: dictionary)
        let transportType = try optionalTransportTypeArgument(in: dictionary)

        return MapKitOpenNavigationRequest(
            source: source,
            destination: destination,
            transportType: transportType
        )
    }

    private func requiredRouteEndpointArgument(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> MapKitRouteEndpoint {
        let endpointDictionary = SchemaTrustedPayload.requiredObject(dictionary, key)
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
}

import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func openNavigation(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseOpenNavigationArguments(payloadJson)
            let result = try store.openNavigation(request: arguments)
            let labeled = MapKitOpenNavigationResult(
                source: MapKitPlaceNames.labeled(result.source, endpoint: arguments.source),
                destination: MapKitPlaceNames.labeled(result.destination, endpoint: arguments.destination),
                transportType: result.transportType,
                directionsMode: result.directionsMode,
                opened: result.opened
            )
            let payloadObject = MapKitSerialization.openNavigationResponseJSONObject(result: labeled)
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
        let source = try routeEndpoint(named: "source", in: dictionary)
        let destination = try routeEndpoint(named: "destination", in: dictionary)
        let transportType = try optionalTransportTypeArgument(in: dictionary)

        return MapKitOpenNavigationRequest(
            source: source,
            destination: destination,
            transportType: transportType
        )
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

import CoreLocation
import Foundation
import MapKit

extension MapKitProvider {
    func calculateRoute(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseCalculateRouteArguments(payloadJson)
            let result = try store.calculateRoute(request: arguments)
            let labeled = MapKitCalculateRouteResult(
                source: MapKitPlaceNames.labeled(result.source, endpoint: arguments.source),
                destination: MapKitPlaceNames.labeled(result.destination, endpoint: arguments.destination),
                routes: result.routes
            )
            let payloadObject = MapKitSerialization.calculateRouteResponseJSONObject(result: labeled)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseCalculateRouteArguments(_ payloadJson: String) throws -> MapKitCalculateRouteRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let source = try routeEndpoint(named: "source", in: dictionary)
        let destination = try routeEndpoint(named: "destination", in: dictionary)
        let transportType = try optionalTransportTypeArgument(in: dictionary)
        let requestsAlternateRoutes = try optionalBoolArgument(named: "requests_alternate_routes", in: dictionary) ??
            false
        let departureDate = try optionalISO8601DateArgument(named: "departure_date", in: dictionary)
        let arrivalDate = try optionalISO8601DateArgument(named: "arrival_date", in: dictionary)

        if departureDate != nil, arrivalDate != nil {
            throw MapKitProviderError.invalidArguments("provide departure_date or arrival_date, not both")
        }

        let tollPreference = try optionalRoutePreferenceArgument(named: "toll_preference", in: dictionary)
        let highwayPreference = try optionalRoutePreferenceArgument(named: "highway_preference", in: dictionary)

        return MapKitCalculateRouteRequest(
            source: source,
            destination: destination,
            transportType: transportType,
            requestsAlternateRoutes: requestsAlternateRoutes,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            tollPreference: tollPreference,
            highwayPreference: highwayPreference
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

    private func optionalRoutePreferenceArgument(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> MKDirections.RoutePreference {
        guard dictionary.keys.contains(key) else {
            return .any
        }

        if dictionary[key] is NSNull {
            return .any
        }

        guard let rawValue = dictionary[key] as? String else {
            throw MapKitProviderError.invalidArguments("\(key) must be a string or null")
        }

        switch rawValue {
        case "any":
            return .any
        case "avoid":
            return .avoid
        default:
            throw MapKitProviderError.invalidArguments("\(key) must be one of: any, avoid")
        }
    }

    private func optionalBoolArgument(named key: String, in dictionary: [String: Any]) throws -> Bool? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? Bool else {
            throw MapKitProviderError.invalidArguments("\(key) must be a boolean or null")
        }

        return value
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

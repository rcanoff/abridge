import Foundation

extension MapKitProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "search_places":
            searchPlaces(payloadJson: payloadJson)
        case "search_nearby":
            searchNearby(payloadJson: payloadJson)
        case "reverse_geocode":
            reverseGeocode(payloadJson: payloadJson)
        case "forward_geocode":
            forwardGeocode(payloadJson: payloadJson)
        case "calculate_route":
            calculateRoute(payloadJson: payloadJson)
        case "estimate_travel_time":
            estimateTravelTime(payloadJson: payloadJson)
        case "lookup_place":
            lookupPlace(payloadJson: payloadJson)
        case "open_navigation":
            openNavigation(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown mapkit operation: \(operation)")
        }
    }
}

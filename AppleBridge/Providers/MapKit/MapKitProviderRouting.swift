import Foundation

extension MapKitProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "search_places":
            searchPlaces(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown mapkit operation: \(operation)")
        }
    }
}

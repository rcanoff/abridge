import Foundation

extension CoreLocationProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "get_current_location":
            getCurrentLocation(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown corelocation operation: \(operation)")
        }
    }
}

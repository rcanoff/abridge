import Foundation

extension VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "recognize_text":
            recognizeText(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}
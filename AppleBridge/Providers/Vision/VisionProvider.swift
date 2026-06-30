import Foundation

@MainActor
enum LiveVisionEnvironment {
    static let sharedProvider = VisionProvider()
}

@MainActor
struct VisionProvider {
    func handle(operation: String, payloadJson _: String) -> ProviderResponse {
        let payload: [String: String] = [
            "code": "unknown_operation",
            "message": "Unknown vision operation: \(operation)",
        ]
        let errorJson = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"code":"unknown_operation"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}

import Foundation

final class AppleProviderBridge: ProviderBridge, @unchecked Sendable {
    private let eventKitProvider: EventKitProvider

    init(eventKitProvider: EventKitProvider = EventKitProvider()) {
        self.eventKitProvider = eventKitProvider
    }

    func callProvider(request: ProviderRequest) -> ProviderResponse {
        switch request.provider {
        case "eventkit":
            return eventKitProvider.handle(operation: request.operation, payloadJson: request.payloadJson)
        default:
            let payload: [String: String] = [
                "code": "unknown_provider",
                "message": "Unknown provider: \(request.provider)",
            ]
            let errorJson = (try? JSONSerialization.data(withJSONObject: payload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"code":"unknown_provider"}"#
            return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
        }
    }
}
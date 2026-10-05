import Foundation

enum VisionProviderError: Error, Equatable {
    case serializationFailed
    case visionError(String)
    case invalidArguments(String)
}

@MainActor
enum LiveVisionEnvironment {
    static let sharedProvider = VisionProvider()
}

/// Adapter layer; pure schema validation is Rust (`arg_validation`).
@MainActor
struct VisionProvider {
    let store: any VisionStoreing

    init(store: any VisionStoreing = LiveVisionStore()) {
        self.store = store
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VisionProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw VisionProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    func providerErrorResponse(from error: VisionProviderError) -> ProviderResponse {
        switch error {
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "vision_error", message: "Failed to serialize Vision response")
        case let .visionError(message):
            errorResponse(code: "vision_error", message: message)
        }
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? VisionSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}

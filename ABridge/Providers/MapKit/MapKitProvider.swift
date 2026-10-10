import Foundation

enum MapKitProviderError: Error, Equatable {
    case serializationFailed
    case mapkitError(String)
    case invalidArguments(String)
}

extension MapKitProviderError: MainQueueCallbackWaitFailure {
    static func callbackWaitFailed(_ message: String) -> Self {
        .mapkitError(message)
    }
}

enum LiveMapKitEnvironment {
    /// Immutable after lazy init; process-wide singleton for the menu-bar agent.
    nonisolated(unsafe) static let sharedProvider = MapKitProvider(
        store: LiveMapKitStore()
    )
}

/// Not `@MainActor`: Rust FFI calls this from background threads. Holding `main.sync` across
/// MapKit waits prevents network completions; `MapKitSearchFetch.waitForCompletion` hops starts
/// to main and waits off-main instead.
/// Adapter layer; pure schema validation is Rust (`arg_validation`).
struct MapKitProvider {
    let store: any MapKitStoreing

    init(store: any MapKitStoreing = LiveMapKitStore()) {
        self.store = store
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MapKitProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    func providerErrorResponse(from error: MapKitProviderError) -> ProviderResponse {
        switch error {
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "mapkit_error", message: "Failed to serialize MapKit response")
        case let .mapkitError(message):
            errorResponse(code: "mapkit_error", message: message)
        }
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? MapKitSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}

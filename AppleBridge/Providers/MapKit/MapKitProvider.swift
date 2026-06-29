import CoreLocation
import Foundation

enum MapKitProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case mapkitError(String)
    case invalidArguments(String)
}

@MainActor
enum LiveMapKitEnvironment {
    static let sharedProvider = MapKitProvider()
}

@MainActor
struct MapKitProvider {
    let store: any MapKitStoreing

    init(store: any MapKitStoreing = LiveMapKitStore()) {
        self.store = store
    }

    var isLocationAuthorized: Bool {
        LocationPermissionStatusMapper.map(store.locationAuthorizationStatus()).grantsReadAccess
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
        case .permissionDenied:
            errorResponse(code: "permission_denied", message: "Location access not granted")
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
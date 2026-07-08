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
    /// Uses the same sticky `LocationPermissionService` as Permissions UI / SettingsStore.
    static let sharedProvider = MapKitProvider(
        store: LiveMapKitStore(),
        locationPermissionChecking: LiveLocationPermission.service
    )
}

@MainActor
struct MapKitProvider {
    let store: any MapKitStoreing
    /// When set (production), MCP location gates match UI sticky reconciliation.
    /// Tests omit this and fall back to the store's raw `CLAuthorizationStatus`.
    private let locationPermissionChecking: (any LocationPermissionChecking)?

    init(
        store: any MapKitStoreing = LiveMapKitStore(),
        locationPermissionChecking: (any LocationPermissionChecking)? = nil
    ) {
        self.store = store
        self.locationPermissionChecking = locationPermissionChecking
    }

    var isLocationAuthorized: Bool {
        if let locationPermissionChecking {
            return locationPermissionChecking.currentStatus().grantsReadAccess
        }
        return LocationPermissionStatusMapper.map(store.locationAuthorizationStatus()).grantsReadAccess
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

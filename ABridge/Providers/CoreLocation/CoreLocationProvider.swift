import CoreLocation
import Foundation

enum CoreLocationProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case corelocationError(String)
    case invalidArguments(String)
}

extension CoreLocationProviderError: MainQueueCallbackWaitFailure {
    static func callbackWaitFailed(_ message: String) -> Self {
        .corelocationError(message)
    }
}

enum LiveCoreLocationEnvironment {
    /// Uses the same sticky `LocationPermissionService` as Permissions UI / SettingsStore.
    /// Immutable after lazy init; process-wide singleton for the menu-bar agent.
    nonisolated(unsafe) static let sharedProvider = CoreLocationProvider(
        store: LiveCoreLocationStore(),
        locationGrantsReadAccess: {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    LiveLocationPermission.service.currentStatus().grantsReadAccess
                }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    LiveLocationPermission.service.currentStatus().grantsReadAccess
                }
            }
        }
    )
}

/// Not `@MainActor`: Rust FFI calls this from background threads. Holding `main.sync` across
/// Core Location waits prevents delegate callbacks; `CoreLocationFetch.waitForCompletion` hops
/// starts to main and waits off-main instead.
/// Adapter layer; pure schema validation is Rust (`arg_validation`).
struct CoreLocationProvider {
    let store: any CoreLocationStoreing
    /// Production uses sticky `LiveLocationPermission`; tests fall back to store CL status.
    private let locationGrantsReadAccess: () -> Bool

    init(
        store: any CoreLocationStoreing = LiveCoreLocationStore(),
        locationGrantsReadAccess: (() -> Bool)? = nil
    ) {
        self.store = store
        if let locationGrantsReadAccess {
            self.locationGrantsReadAccess = locationGrantsReadAccess
        } else {
            self.locationGrantsReadAccess = {
                LocationPermissionStatusMapper.map(store.locationAuthorizationStatus()).grantsReadAccess
            }
        }
    }

    var isLocationAuthorized: Bool {
        locationGrantsReadAccess()
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CoreLocationProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw CoreLocationProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    func providerErrorResponse(from error: CoreLocationProviderError) -> ProviderResponse {
        switch error {
        case .permissionDenied:
            errorResponse(code: "permission_denied", message: "Location access not granted")
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "corelocation_error", message: "Failed to serialize Core Location response")
        case let .corelocationError(message):
            errorResponse(code: "corelocation_error", message: message)
        }
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? CoreLocationSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}

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
        locationPermissionStatus: {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    LiveLocationPermission.service.currentStatus()
                }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    LiveLocationPermission.service.currentStatus()
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
    private let locationPermissionStatus: () -> LocationPermissionStatus
    /// Production reads `CLLocationManager`; tests inject a fixed answer.
    private let locationServicesEnabled: () -> Bool

    static let locationServicesOffMessage =
        "Location Services are turned off, so this Mac has no position. "
            + "Turn them on in System Settings > Privacy & Security > Location Services, then try again."
    static let permissionDeniedMessage =
        "Location permission is denied. "
            + "Allow ABridge in System Settings > Privacy & Security > Location Services, then try again."
    static let permissionNotDeterminedMessage =
        "Location permission is not determined. Allow ABridge to use your location "
            + "in System Settings > Privacy & Security > Location Services, then try again."
    static let permissionRestrictedMessage =
        "Location permission is restricted by a device policy. Allow location access for ABridge, then try again."
    static let locationUnknownMessage =
        "No location fix. Core Location returned locationUnknown (kCLErrorDomain error 0) or the request timed out. "
            + "Move near a window or outside, confirm Location Services and "
            + "ABridge's location permission are on, then try again."

    init(
        store: any CoreLocationStoreing = LiveCoreLocationStore(),
        locationPermissionStatus: (() -> LocationPermissionStatus)? = nil,
        locationServicesEnabled: (() -> Bool)? = nil
    ) {
        self.store = store
        if let locationPermissionStatus {
            self.locationPermissionStatus = locationPermissionStatus
        } else {
            self.locationPermissionStatus = {
                LocationPermissionStatusMapper.map(store.locationAuthorizationStatus())
            }
        }
        self.locationServicesEnabled = locationServicesEnabled ?? { CLLocationManager.locationServicesEnabled() }
    }

    var isLocationAuthorized: Bool {
        locationPermissionStatus().grantsReadAccess
    }

    func locationAccessError() -> ProviderResponse? {
        if !locationServicesEnabled() {
            return errorResponse(code: "location_services_off", message: Self.locationServicesOffMessage)
        }
        switch locationPermissionStatus() {
        case .authorized, .authorizedAlways:
            return nil
        case .notDetermined:
            return errorResponse(code: "permission_denied", message: Self.permissionNotDeterminedMessage)
        case .restricted:
            return errorResponse(code: "permission_denied", message: Self.permissionRestrictedMessage)
        case .denied, .unknown:
            return errorResponse(code: "permission_denied", message: Self.permissionDeniedMessage)
        }
    }

    func locationFailureResponse(for error: Error) -> ProviderResponse {
        if let providerError = error as? CoreLocationProviderError {
            if case let .corelocationError(message) = providerError,
               message.localizedCaseInsensitiveContains("timed out")
            {
                return errorResponse(code: "location_unknown", message: Self.locationUnknownMessage)
            }
            return providerErrorResponse(from: providerError)
        }
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain {
            switch CLError.Code(rawValue: nsError.code) {
            case .locationUnknown:
                return errorResponse(code: "location_unknown", message: Self.locationUnknownMessage)
            case .denied:
                return errorResponse(code: "permission_denied", message: Self.permissionDeniedMessage)
            default:
                break
            }
        }
        return errorResponse(code: "corelocation_error", message: error.localizedDescription)
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
            errorResponse(code: "permission_denied", message: Self.permissionDeniedMessage)
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

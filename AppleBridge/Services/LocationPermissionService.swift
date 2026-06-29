@preconcurrency import CoreLocation
import Foundation

enum LocationPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class LocationPermissionService: LocationPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> CLAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> LocationPermissionStatus

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var sessionStatus: LocationPermissionStatus?

    init(
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            CLLocationManager().authorizationStatus
        }
        self.requestAccessHandler = requestAccessHandler ?? {
            try await Self.requestAccess()
        }
    }

    func currentStatus() -> LocationPermissionStatus {
        let mapped = LocationPermissionStatusMapper.map(authorizationStatusProvider())
        if mapped != .notDetermined {
            sessionStatus = nil
            return mapped
        }
        return sessionStatus ?? mapped
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        let result = try await requestAccessHandler()
        if result.grantsReadAccess {
            sessionStatus = result
        } else {
            sessionStatus = nil
        }
        return result
    }

    private static func requestAccess() async throws -> LocationPermissionStatus {
        try await AuthorizationRequestLocationManager().requestWhenInUseAuthorization()
    }
}

@MainActor
private final class AuthorizationRequestLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationPermissionStatus, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseAuthorization() async throws -> LocationPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
            resumeIfDetermined()
        }
    }

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        resumeIfDetermined()
    }

    private func resumeIfDetermined() {
        let status = LocationPermissionStatusMapper.map(manager.authorizationStatus)
        guard status != .notDetermined, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: status)
    }
}
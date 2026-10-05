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
enum LocationAuthorizationWait {
    /// Upper bound for blocking while CoreLocation delivers its authorization callback.
    static let defaultTimeout: TimeInterval = 30
    static let pollInterval: Duration = .milliseconds(10)

    static func waitUntilDetermined(
        timeout: TimeInterval = defaultTimeout,
        isDetermined: () -> Bool,
        onCheck: () -> Void = {}
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !isDetermined(), Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            onCheck()
            if isDetermined() { return }
            try await Task.sleep(for: pollInterval)
        }

        guard isDetermined() else {
            throw LocationPermissionError.requestFailed("Location authorization request timed out.")
        }
    }
}

/// Process-stable CoreLocation status reader. Ephemeral `CLLocationManager()` instances
/// can flap between authorized and notDetermined under ad-hoc Debug builds; retain one manager.
@MainActor
enum LiveLocationAuthorization {
    static let manager = CLLocationManager()

    static func authorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Safe from any thread (short `main.sync` hop when needed).
    nonisolated static func authorizationStatusFromAnyThread() -> CLAuthorizationStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { authorizationStatus() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { authorizationStatus() }
        }
    }
}

/// Shared location permission service for UI + MapKit MCP gates so both see the same sticky status.
@MainActor
enum LiveLocationPermission {
    static let service = LocationPermissionService()
}

@MainActor
final class LocationPermissionService: LocationPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> CLAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> LocationPermissionStatus

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var reconciliationState: LocationPermissionStatusReconciliation.State

    init(
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil,
        authorizationRequestTimeout: TimeInterval = LocationAuthorizationWait.defaultTimeout
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            LiveLocationAuthorization.authorizationStatus()
        }
        self.requestAccessHandler = requestAccessHandler ?? {
            try await Self.requestAccess(timeout: authorizationRequestTimeout)
        }

        let initialStatus = LocationPermissionStatusMapper.map(self.authorizationStatusProvider())
        reconciliationState = LocationPermissionStatusReconciliation.initialState(for: initialStatus)
    }

    func currentStatus() -> LocationPermissionStatus {
        resolveStatus(from: authorizationStatusProvider())
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        let result = try await requestAccessHandler()
        reconciliationState = LocationPermissionStatusReconciliation.afterRequest(
            result: result,
            state: reconciliationState
        )
        // Re-resolve so a successful grant is sticky even if the next system poll is stale.
        return resolveStatus(from: authorizationStatusProvider())
    }

    private func resolveStatus(from clStatus: CLAuthorizationStatus) -> LocationPermissionStatus {
        let mapped = LocationPermissionStatusMapper.map(clStatus)
        let resolved = LocationPermissionStatusReconciliation.resolve(
            systemStatus: mapped,
            state: reconciliationState
        )
        reconciliationState = resolved.state
        return resolved.status
    }

    private static func requestAccess(
        timeout: TimeInterval = LocationAuthorizationWait.defaultTimeout
    ) async throws -> LocationPermissionStatus {
        try await AuthorizationRequestLocationManager(requestTimeout: timeout).requestWhenInUseAuthorization()
    }
}

@MainActor
private final class AuthorizationRequestLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationPermissionStatus, Error>?
    private let requestTimeout: TimeInterval

    init(requestTimeout: TimeInterval = LocationAuthorizationWait.defaultTimeout) {
        self.requestTimeout = requestTimeout
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseAuthorization() async throws -> LocationPermissionStatus {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
                resumeIfDetermined()

                guard self.continuation != nil else { return }

                Task { @MainActor in
                    await self.waitForDeterminationOrTimeout()
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelPendingRequest()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        resumeIfDetermined()
    }

    private func waitForDeterminationOrTimeout() async {
        do {
            try await LocationAuthorizationWait.waitUntilDetermined(timeout: requestTimeout) {
                manager.authorizationStatus != .notDetermined
            } onCheck: {
                self.resumeIfDetermined()
            }
        } catch is CancellationError {
            cancelPendingRequest()
        } catch {
            resumeWithFailureIfStillPending(error)
        }
    }

    private func resumeIfDetermined() {
        let status = LocationPermissionStatusMapper.map(manager.authorizationStatus)
        guard status != .notDetermined, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: status)
    }

    private func resumeWithFailureIfStillPending(_ error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    private func cancelPendingRequest() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: CancellationError())
    }
}

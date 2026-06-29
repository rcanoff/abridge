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
    static let runLoopInterval: TimeInterval = 0.01

    static func waitUntilDetermined(
        timeout: TimeInterval = defaultTimeout,
        isDetermined: () -> Bool,
        onCheck: () -> Void = {}
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !isDetermined(), Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            onCheck()
            if isDetermined() { return }
            EventKitReminderFetch.pumpRunLoop(until: Date(timeIntervalSinceNow: runLoopInterval))
        }

        guard isDetermined() else {
            throw LocationPermissionError.requestFailed("Location authorization request timed out.")
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
        requestAccessHandler: RequestAccessHandler? = nil,
        authorizationRequestTimeout: TimeInterval = LocationAuthorizationWait.defaultTimeout
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            CLLocationManager().authorizationStatus
        }
        self.requestAccessHandler = requestAccessHandler ?? {
            try await Self.requestAccess(timeout: authorizationRequestTimeout)
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
            try LocationAuthorizationWait.waitUntilDetermined(timeout: requestTimeout) {
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

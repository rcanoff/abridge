@testable import AppleBridge
import CoreLocation
import Testing

@Suite("LocationPermissionService")
struct LocationPermissionServiceTests {
    @Test
    @MainActor
    func currentStatusMapsAuthorizationStatus() {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .authorizedAlways }
        )
        #expect(service.currentStatus() == .authorized)
    }

    @Test
    @MainActor
    func requestAccessReturnsHandlerResult() async throws {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )
        let result = try await service.requestAccess()
        #expect(result == .authorized)
        #expect(service.currentStatus() == .authorized)
    }

    @Test
    @MainActor
    func requestAccessSurfacesError() async {
        let service = LocationPermissionService(
            requestAccessHandler: { throw LocationPermissionError.requestFailed("denied") }
        )
        await #expect(throws: LocationPermissionError.self) {
            _ = try await service.requestAccess()
        }
    }

    @Test
    @MainActor
    func currentStatusUsesSessionGrantWhenAuthorizationStillNotDetermined() async throws {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )
        _ = try await service.requestAccess()
        #expect(service.currentStatus().grantsReadAccess)
    }

    @Test
    @MainActor
    func waitUntilDeterminedTimesOutWhenAuthorizationStaysNotDetermined() {
        let timeout: TimeInterval = 0.1
        let started = ContinuousClock.now

        #expect(throws: LocationPermissionError.self) {
            try LocationAuthorizationWait.waitUntilDetermined(timeout: timeout) {
                false
            }
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(timeout + 0.25))
    }

    @Test
    @MainActor
    func waitUntilDeterminedResumesWhenAuthorizationBecomesDetermined() throws {
        var status: CLAuthorizationStatus = .notDetermined

        try LocationAuthorizationWait.waitUntilDetermined(timeout: 0.1) {
            status != .notDetermined
        } onCheck: {
            status = .authorized
        }
    }

    @Test
    @MainActor
    func requestAccessSurfacesTimeoutFromAuthorizationWait() async {
        let service = LocationPermissionService(
            requestAccessHandler: {
                try LocationAuthorizationWait.waitUntilDetermined(timeout: 0.1) {
                    false
                }
                return .authorized
            }
        )

        await #expect(throws: LocationPermissionError.self) {
            _ = try await service.requestAccess()
        }
    }
}
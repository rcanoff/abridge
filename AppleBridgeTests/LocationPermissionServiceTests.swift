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
    func waitUntilDeterminedTimesOutWhenAuthorizationStaysNotDetermined() async {
        let timeout: TimeInterval = 0.1
        let started = ContinuousClock.now

        await #expect(throws: LocationPermissionError.self) {
            try await LocationAuthorizationWait.waitUntilDetermined(timeout: timeout) {
                false
            }
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(timeout + 0.25))
    }

    @Test
    @MainActor
    func waitUntilDeterminedResumesWhenAuthorizationBecomesDetermined() async throws {
        var status: CLAuthorizationStatus = .notDetermined

        try await LocationAuthorizationWait.waitUntilDetermined(timeout: 0.1) {
            status != .notDetermined
        } onCheck: {
            status = .authorized
        }
    }

    @Test
    @MainActor
    func waitUntilDeterminedSuspendsMainActor() async throws {
        let timeout: TimeInterval = 0.2
        var counter = 0

        let waitTask = Task { @MainActor in
            try await LocationAuthorizationWait.waitUntilDetermined(timeout: timeout) {
                false
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        counter += 1
        #expect(counter == 1)

        await #expect(throws: LocationPermissionError.self) {
            try await waitTask.value
        }
    }

    @Test
    @MainActor
    func requestAccessSurfacesTimeoutFromAuthorizationWait() async {
        let service = LocationPermissionService(
            requestAccessHandler: {
                try await LocationAuthorizationWait.waitUntilDetermined(timeout: 0.1) {
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

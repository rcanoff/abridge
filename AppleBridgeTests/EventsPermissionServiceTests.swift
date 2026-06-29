@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventsPermissionService")
struct EventsPermissionServiceTests {
    @Test
    @MainActor
    func currentStatusMapsFullAccessToAuthorized() {
        let service = EventsPermissionService {
            .fullAccess
        }

        #expect(service.currentStatus() == .authorized)
        #expect(service.currentStatus().grantsReadAccess)
    }

    @Test
    @MainActor
    func currentStatusMapsDeniedWithoutReadAccess() {
        let service = EventsPermissionService {
            .denied
        }

        #expect(service.currentStatus() == .denied)
        #expect(service.currentStatus().grantsReadAccess == false)
    }

    @Test
    @MainActor
    func currentStatusPreservesAuthorizedAfterRequestWhenEventKitStatusIsStale() async throws {
        let service = EventsPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )

        _ = try await service.requestAccess()

        #expect(service.currentStatus() == .authorized)
        #expect(service.currentStatus().grantsReadAccess)
    }

    @Test
    @MainActor
    func currentStatusClearsSessionGrantWhenEventKitReportsDenied() async throws {
        var eventKitStatus: EKAuthorizationStatus = .notDetermined
        let service = EventsPermissionService(
            authorizationStatusProvider: { eventKitStatus },
            requestAccessHandler: { .authorized }
        )

        _ = try await service.requestAccess()
        eventKitStatus = .denied

        #expect(service.currentStatus() == .denied)
        #expect(service.currentStatus().grantsReadAccess == false)
    }

    @Test
    @MainActor
    func requestAccessReturnsHandlerResult() async throws {
        let service = EventsPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )

        let result = try await service.requestAccess()
        #expect(result == .authorized)
    }

    @Test
    @MainActor
    func requestAccessSurfacesError() async {
        let service = EventsPermissionService(
            requestAccessHandler: { throw EventsPermissionError.requestFailed("denied") }
        )

        await #expect(throws: EventsPermissionError.self) {
            _ = try await service.requestAccess()
        }
    }
}
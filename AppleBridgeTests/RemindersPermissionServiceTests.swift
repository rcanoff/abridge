@testable import AppleBridge
import EventKit
import Testing

@Suite("RemindersPermissionService")
struct RemindersPermissionServiceTests {
    @Test
    @MainActor
    func currentStatusPreservesAuthorizedAfterRequestWhenEventKitStatusIsStale() async throws {
        let service = RemindersPermissionService(
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
        let service = RemindersPermissionService(
            authorizationStatusProvider: { eventKitStatus },
            requestAccessHandler: { .authorized }
        )

        _ = try await service.requestAccess()
        eventKitStatus = .denied

        #expect(service.currentStatus() == .denied)
        #expect(service.currentStatus().grantsReadAccess == false)
    }
}

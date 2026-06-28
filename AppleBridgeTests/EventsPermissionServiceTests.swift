@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventsPermissionService")
struct EventsPermissionServiceTests {
    @Test
    @MainActor
    func grantsReadAccessWhenProviderReportsFullAccess() {
        let service = EventsPermissionService {
            .fullAccess
        }

        #expect(service.grantsReadAccess())
    }

    @Test
    @MainActor
    func deniesReadAccessWhenProviderReportsDenied() {
        let service = EventsPermissionService {
            .denied
        }

        #expect(!service.grantsReadAccess())
    }
}

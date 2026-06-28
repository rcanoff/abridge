@testable import AppleBridge
import Foundation

@MainActor
final class MockEventsPermissionService: EventsPermissionChecking {
    var grantsReadAccessValue = false

    func grantsReadAccess() -> Bool {
        grantsReadAccessValue
    }
}

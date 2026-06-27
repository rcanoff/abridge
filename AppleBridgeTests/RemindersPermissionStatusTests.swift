import EventKit
import Testing
@testable import AppleBridge

@Suite("RemindersPermissionStatusMapper")
struct RemindersPermissionStatusTests {
    @Test func mapsNotDetermined() {
        #expect(
            RemindersPermissionStatusMapper.map(.notDetermined) == .notDetermined
        )
    }

    @Test func mapsFullAccessToAuthorized() {
        #expect(
            RemindersPermissionStatusMapper.map(.fullAccess) == .authorized
        )
    }

    @Test func mapsWriteOnlyToAuthorized() {
        #expect(
            RemindersPermissionStatusMapper.map(.writeOnly) == .authorized
        )
    }

    @Test func mapsDenied() {
        #expect(
            RemindersPermissionStatusMapper.map(.denied) == .denied
        )
    }

    @Test func mapsRestricted() {
        #expect(
            RemindersPermissionStatusMapper.map(.restricted) == .restricted
        )
    }

    @Test func displayNameIsNonEmptyForAllCases() {
        for status in RemindersPermissionStatus.allCases {
            #expect(status.displayName.isEmpty == false)
        }
    }
}
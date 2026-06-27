@testable import AppleBridge
import EventKit
import Testing

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

    @Test func mapsWriteOnlyToWriteOnly() {
        #expect(
            RemindersPermissionStatusMapper.map(.writeOnly) == .writeOnly
        )
    }

    @Test func writeOnlyDoesNotGrantReadAccess() {
        #expect(RemindersPermissionStatus.writeOnly.grantsReadAccess == false)
        #expect(RemindersPermissionStatus.authorized.grantsReadAccess == true)
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

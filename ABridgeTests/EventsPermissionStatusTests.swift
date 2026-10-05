@testable import ABridge
import EventKit
import Testing

@Suite("EventsPermissionStatusMapper")
struct EventsPermissionStatusTests {
    @Test func mapsNotDetermined() {
        #expect(
            EventsPermissionStatusMapper.map(.notDetermined) == .notDetermined
        )
    }

    @Test func mapsFullAccessToAuthorized() {
        #expect(
            EventsPermissionStatusMapper.map(.fullAccess) == .authorized
        )
    }

    @Test func mapsWriteOnlyToWriteOnly() {
        #expect(
            EventsPermissionStatusMapper.map(.writeOnly) == .writeOnly
        )
    }

    @Test func writeOnlyDoesNotGrantReadAccess() {
        #expect(EventsPermissionStatus.writeOnly.grantsReadAccess == false)
        #expect(EventsPermissionStatus.authorized.grantsReadAccess == true)
    }

    @Test func mapsDenied() {
        #expect(
            EventsPermissionStatusMapper.map(.denied) == .denied
        )
    }

    @Test func mapsRestricted() {
        #expect(
            EventsPermissionStatusMapper.map(.restricted) == .restricted
        )
    }

    @Test func displayNameIsNonEmptyForAllCases() {
        for status in EventsPermissionStatus.allCases {
            #expect(status.displayName.isEmpty == false)
        }
    }
}

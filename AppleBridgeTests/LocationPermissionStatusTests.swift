@testable import AppleBridge
import CoreLocation
import Testing

@Suite("LocationPermissionStatus")
struct LocationPermissionStatusTests {
    @Test
    func mapNotDetermined() {
        #expect(LocationPermissionStatusMapper.map(.notDetermined) == .notDetermined)
    }

    @Test
    func mapAuthorizedGrantsReadAccess() {
        let status = LocationPermissionStatusMapper.map(.authorized)
        #expect(status == .authorized)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapAuthorizedAlwaysGrantsReadAccess() {
        let status = LocationPermissionStatusMapper.map(.authorizedAlways)
        // On macOS, .authorized and .authorizedAlways share the same CLAuthorizationStatus value.
        #expect(status == .authorized)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapDeniedDoesNotGrantReadAccess() {
        let status = LocationPermissionStatusMapper.map(.denied)
        #expect(status.grantsReadAccess == false)
    }
}

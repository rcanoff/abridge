@testable import ABridge
import CoreLocation

final class MockCoreLocationStore: CoreLocationStoreing, @unchecked Sendable {
    var authorizationStatus: CLAuthorizationStatus = .authorized
    var getCurrentLocationResult: CLLocation?
    var getCurrentLocationError: Error?
    private(set) var getCurrentLocationCallCount = 0

    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        authorizationStatus
    }

    func getCurrentLocation() throws -> CLLocation {
        getCurrentLocationCallCount += 1
        if let getCurrentLocationError {
            throw getCurrentLocationError
        }
        if let getCurrentLocationResult {
            return getCurrentLocationResult
        }
        return CLLocation(latitude: 0, longitude: 0)
    }
}

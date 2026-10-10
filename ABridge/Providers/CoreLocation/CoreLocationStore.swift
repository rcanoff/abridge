import CoreLocation

protocol CoreLocationStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func getCurrentLocation() throws -> CLLocation
}

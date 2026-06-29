import CoreLocation
import MapKit
@testable import AppleBridge

@MainActor
final class MockMapKitStore: MapKitStoreing {
    var authorizationStatus: CLAuthorizationStatus = .authorized
    var results: [MapKitSearchResult] = []
    private(set) var lastRequest: MapKitSearchRequest?

    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        authorizationStatus
    }

    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        lastRequest = request
        if let first = results.first {
            return first
        }
        return MapKitSearchResult(mapItems: [], boundingRegion: nil)
    }
}
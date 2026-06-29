import CoreLocation
import MapKit

struct MapKitSearchResult {
    let mapItems: [MKMapItem]
    let boundingRegion: MKCoordinateRegion?
}

struct MapKitSearchRequest {
    let query: String
    let region: MKCoordinateRegion?
    let regionPriority: MKLocalSearchRegionPriority
    let resultTypes: MKLocalSearch.ResultType?
}

struct MapKitSearchNearbyRequest {
    let region: MKCoordinateRegion
    let pointOfInterestFilter: MKPointOfInterestFilter?
}

struct MapKitReverseGeocodeRequest {
    let coordinate: CLLocationCoordinate2D
}

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem]
}

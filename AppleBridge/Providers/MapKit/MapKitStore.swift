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

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
}

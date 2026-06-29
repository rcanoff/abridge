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

struct MapKitForwardGeocodeRequest {
    let address: String
    let region: MKCoordinateRegion?
    let preferredLocale: Locale?
}

struct MapKitRouteEndpoint {
    let coordinate: CLLocationCoordinate2D
}

struct MapKitCalculateRouteRequest {
    let source: MapKitRouteEndpoint
    let destination: MapKitRouteEndpoint
    let transportType: MKDirectionsTransportType
    let requestsAlternateRoutes: Bool
    let departureDate: Date?
    let arrivalDate: Date?
    let tollPreference: MKDirections.RoutePreference
    let highwayPreference: MKDirections.RoutePreference
}

struct MapKitRouteStepData {
    let instructions: String
    let notice: String?
    let distance: CLLocationDistance
    let transportType: MKDirectionsTransportType
    let polylineCoordinates: [CLLocationCoordinate2D]
    let polylineTitle: String?
    let polylineSubtitle: String?
}

struct MapKitRouteData {
    let name: String
    let advisoryNotices: [String]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let transportType: MKDirectionsTransportType
    let polylineCoordinates: [CLLocationCoordinate2D]
    let polylineTitle: String?
    let polylineSubtitle: String?
    let steps: [MapKitRouteStepData]
    let hasTolls: Bool
    let hasHighways: Bool
}

struct MapKitCalculateRouteResult {
    let source: MKMapItem
    let destination: MKMapItem
    let routes: [MapKitRouteData]
}

struct MapKitEstimateTravelTimeRequest {
    let source: MapKitRouteEndpoint
    let destination: MapKitRouteEndpoint
    let transportType: MKDirectionsTransportType
    let departureDate: Date?
    let arrivalDate: Date?
}

struct MapKitEstimateTravelTimeResult {
    let source: MKMapItem
    let destination: MKMapItem
    let expectedTravelTime: TimeInterval
    let distance: CLLocationDistance
    let expectedArrivalDate: Date
    let expectedDepartureDate: Date
    let transportType: MKDirectionsTransportType
}

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem]
    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem]
    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult
    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult
    func getCurrentLocation() throws -> CLLocation
}

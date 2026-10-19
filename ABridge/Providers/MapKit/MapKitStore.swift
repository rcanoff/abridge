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
    var coordinate: CLLocationCoordinate2D?
    var name: String?
    var identifier: String?
}

enum MapKitPlaceNames {
    static func isPlaceholder(_ name: String?) -> Bool {
        guard let name else { return true }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ||
            trimmed.compare("Unknown Location", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Request name wins. A coordinate-only item keeps a real (including reverse-geocoded) name.
    /// Apple's "Unknown Location" sentinel is cleared so serialization can omit it.
    static func labeled(_ item: MKMapItem, endpoint: MapKitRouteEndpoint) -> MKMapItem {
        if let name = endpoint.name, !isPlaceholder(name) {
            item.name = name
        } else if isPlaceholder(item.name) {
            item.name = nil
        }
        return item
    }

    /// MapKit's response item may drop the name set on the request item.
    static func carryingName(
        from requested: MKMapItem,
        onto response: MKMapItem,
        endpoint: MapKitRouteEndpoint
    ) -> MKMapItem {
        if let name = endpoint.name, !isPlaceholder(name) {
            response.name = name
        } else if isPlaceholder(response.name), let name = requested.name, !isPlaceholder(name) {
            response.name = name
        } else if isPlaceholder(response.name) {
            response.name = nil
        }
        if response.timeZone == nil {
            response.timeZone = requested.timeZone
        }
        return response
    }

    static func jsonValue(_ name: String?) -> Any {
        guard let name, !isPlaceholder(name) else { return NSNull() }
        return name
    }
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

struct MapKitGetPlaceRequest {
    let identifier: String
}

struct MapKitOpenNavigationRequest {
    let source: MapKitRouteEndpoint
    let destination: MapKitRouteEndpoint
    let transportType: MKDirectionsTransportType
}

struct MapKitOpenNavigationResult {
    let source: MKMapItem
    let destination: MKMapItem
    let transportType: MKDirectionsTransportType
    let directionsMode: String?
    let opened: Bool
}

protocol MapKitStoreing {
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem]
    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem]
    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult
    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult
    func getPlace(request: MapKitGetPlaceRequest) throws -> MKMapItem
    func openNavigation(request: MapKitOpenNavigationRequest) throws -> MapKitOpenNavigationResult
}

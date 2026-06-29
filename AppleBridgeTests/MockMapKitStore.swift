@testable import AppleBridge
import CoreLocation
import MapKit

@MainActor
final class MockMapKitStore: MapKitStoreing {
    var authorizationStatus: CLAuthorizationStatus = .authorized
    var results: [MapKitSearchResult] = []
    var nearbyResults: [MapKitSearchResult] = []
    var reverseGeocodeResults: [[MKMapItem]] = []
    var forwardGeocodeResults: [[MKMapItem]] = []
    var calculateRouteResults: [MapKitCalculateRouteResult] = []
    var estimateTravelTimeResults: [MapKitEstimateTravelTimeResult] = []
    private(set) var lastRequest: MapKitSearchRequest?
    private(set) var lastNearbyRequest: MapKitSearchNearbyRequest?
    private(set) var lastReverseGeocodeRequest: MapKitReverseGeocodeRequest?
    private(set) var lastForwardGeocodeRequest: MapKitForwardGeocodeRequest?
    private(set) var lastCalculateRouteRequest: MapKitCalculateRouteRequest?
    private(set) var lastEstimateTravelTimeRequest: MapKitEstimateTravelTimeRequest?

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

    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
        lastNearbyRequest = request
        if let first = nearbyResults.first {
            return first
        }
        return MapKitSearchResult(mapItems: [], boundingRegion: nil)
    }

    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
        lastReverseGeocodeRequest = request
        if let first = reverseGeocodeResults.first {
            return first
        }
        return []
    }

    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
        lastForwardGeocodeRequest = request
        if let first = forwardGeocodeResults.first {
            return first
        }
        return []
    }

    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult {
        lastCalculateRouteRequest = request
        if let first = calculateRouteResults.first {
            return first
        }

        let sourcePlacemark = MKPlacemark(coordinate: request.source.coordinate)
        let destinationPlacemark = MKPlacemark(coordinate: request.destination.coordinate)
        return MapKitCalculateRouteResult(
            source: MKMapItem(placemark: sourcePlacemark),
            destination: MKMapItem(placemark: destinationPlacemark),
            routes: []
        )
    }

    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult {
        lastEstimateTravelTimeRequest = request
        if let first = estimateTravelTimeResults.first {
            return first
        }

        let sourcePlacemark = MKPlacemark(coordinate: request.source.coordinate)
        let destinationPlacemark = MKPlacemark(coordinate: request.destination.coordinate)
        let now = Date(timeIntervalSince1970: 1_718_000_000)
        return MapKitEstimateTravelTimeResult(
            source: MKMapItem(placemark: sourcePlacemark),
            destination: MKMapItem(placemark: destinationPlacemark),
            expectedTravelTime: 0,
            distance: 0,
            expectedArrivalDate: now,
            expectedDepartureDate: now,
            transportType: request.transportType
        )
    }
}

@testable import ABridge
import CoreLocation
import MapKit

final class MockMapKitStore: MapKitStoreing, @unchecked Sendable {
    var authorizationStatus: CLAuthorizationStatus = .authorized
    var results: [MapKitSearchResult] = []
    var nearbyResults: [MapKitSearchResult] = []
    var reverseGeocodeResults: [[MKMapItem]] = []
    var forwardGeocodeResults: [[MKMapItem]] = []
    var calculateRouteResults: [MapKitCalculateRouteResult] = []
    var estimateTravelTimeResults: [MapKitEstimateTravelTimeResult] = []
    var getCurrentLocationResult: CLLocation?
    var getCurrentLocationError: Error?
    private(set) var getCurrentLocationCallCount = 0
    var lookupPlaceResults: [MKMapItem] = []
    var openNavigationResults: [MapKitOpenNavigationResult] = []
    private(set) var lastRequest: MapKitSearchRequest?
    private(set) var lastNearbyRequest: MapKitSearchNearbyRequest?
    private(set) var lastReverseGeocodeRequest: MapKitReverseGeocodeRequest?
    private(set) var lastForwardGeocodeRequest: MapKitForwardGeocodeRequest?
    private(set) var lastCalculateRouteRequest: MapKitCalculateRouteRequest?
    private(set) var lastEstimateTravelTimeRequest: MapKitEstimateTravelTimeRequest?
    private(set) var lastLookupPlaceRequest: MapKitLookupPlaceRequest?
    private(set) var lastOpenNavigationRequest: MapKitOpenNavigationRequest?

    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        authorizationStatus
    }

    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        lastRequest = request; return results.first ?? MapKitSearchResult(mapItems: [], boundingRegion: nil)
    }

    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
        lastNearbyRequest = request; return nearbyResults.first ?? MapKitSearchResult(mapItems: [], boundingRegion: nil)
    }

    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
        lastReverseGeocodeRequest = request; return reverseGeocodeResults.first ?? []
    }

    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
        lastForwardGeocodeRequest = request; return forwardGeocodeResults.first ?? []
    }

    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult {
        lastCalculateRouteRequest = request
        if let first = calculateRouteResults.first {
            return first
        }
        return MapKitCalculateRouteResult(
            source: MapKitTestFixtures.mapItem(coordinate: request.source.coordinate),
            destination: MapKitTestFixtures.mapItem(coordinate: request.destination.coordinate),
            routes: []
        )
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

    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult {
        lastEstimateTravelTimeRequest = request
        if let first = estimateTravelTimeResults.first {
            return first
        }

        let now = Date(timeIntervalSince1970: 1_718_000_000)
        return MapKitEstimateTravelTimeResult(
            source: MapKitTestFixtures.mapItem(coordinate: request.source.coordinate),
            destination: MapKitTestFixtures.mapItem(coordinate: request.destination.coordinate),
            expectedTravelTime: 0,
            distance: 0,
            expectedArrivalDate: now,
            expectedDepartureDate: now,
            transportType: request.transportType
        )
    }

    func lookupPlace(request: MapKitLookupPlaceRequest) throws -> MKMapItem {
        lastLookupPlaceRequest = request
        if let first = lookupPlaceResults.first {
            return first
        }

        return MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
    }

    func openNavigation(request: MapKitOpenNavigationRequest) throws -> MapKitOpenNavigationResult {
        lastOpenNavigationRequest = request
        if let first = openNavigationResults.first {
            return first
        }

        return MapKitOpenNavigationResult(
            source: MapKitTestFixtures.mapItem(coordinate: request.source.coordinate),
            destination: MapKitTestFixtures.mapItem(coordinate: request.destination.coordinate),
            transportType: request.transportType,
            directionsMode: nil,
            opened: true
        )
    }
}

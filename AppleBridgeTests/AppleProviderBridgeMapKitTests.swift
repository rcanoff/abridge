@testable import AppleBridge
import CoreLocation
import Foundation
import MapKit
import Testing

@Suite("AppleProviderBridgeMapKit")
struct AppleProviderBridgeMapKitTests {
    @Test
    @MainActor
    func callProviderMapKitSearchPlacesSucceedsWithMockStore() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Mock Cafe"
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.results = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "search_places",
            payloadJson: #"{"query":"coffee"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Mock Cafe")
    }

    @Test
    @MainActor
    func callProviderMapKitSearchNearbySucceedsWithMockStore() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Nearby Mock Cafe"
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.nearbyResults = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.3346,"longitude":-122.0090},"radius_meters":500}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Nearby Mock Cafe")
    }

    @Test
    @MainActor
    func callProviderMapKitReverseGeocodeSucceedsWithMockStore() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Reverse Mock Address"
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.reverseGeocodeResults = [[item]]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "reverse_geocode",
            payloadJson: #"{"coordinate":{"latitude":37.3346,"longitude":-122.0090}}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Reverse Mock Address")
    }

    @Test
    @MainActor
    func callProviderMapKitForwardGeocodeSucceedsWithMockStore() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Forward Mock Address"
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.forwardGeocodeResults = [[item]]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "forward_geocode",
            payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Forward Mock Address")
    }

    @Test
    @MainActor
    func callProviderMapKitCalculateRouteSucceedsWithMockStore() throws {
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Route Source"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "Route Destination"
        let route = MapKitRouteData(
            name: "Mock Route",
            advisoryNotices: [],
            distance: 1000,
            expectedTravelTime: 600,
            transportType: .automobile,
            polylineCoordinates: [sourcePlacemark.coordinate, destinationPlacemark.coordinate],
            polylineTitle: nil,
            polylineSubtitle: nil,
            steps: [],
            hasTolls: false,
            hasHighways: false
        )
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.calculateRouteResults = [
            MapKitCalculateRouteResult(
                source: sourceItem,
                destination: destinationItem,
                routes: [route]
            ),
        ]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "calculate_route",
            payloadJson: calculateRoutePayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194
            )
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let routes = decoded?["routes"] as? [[String: Any]]
        #expect(routes?.first?["name"] as? String == "Mock Route")
    }

    @Test @MainActor func callProviderMapKitGetCurrentLocationSucceedsWithMockStore() throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            course: -1.0,
            speed: -1.0,
            timestamp: Date(timeIntervalSince1970: 1_751_280_000)
        )
        let store = MockMapKitStore(); store.authorizationStatus = .authorized; store
            .getCurrentLocationResult = location
        let response = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))
            .callProvider(request: ProviderRequest(
                provider: "mapkit",
                operation: "get_current_location",
                payloadJson: "{}"
            ))
        #expect(response.ok == true)
        let decoded = try JSONSerialization
            .jsonObject(with: #require(response.payloadJson.data(using: .utf8))) as? [String: Any]
        #expect(((decoded?["location"] as? [String: Any])?["coordinate"] as? [String: Any])?["latitude"] as? Double ==
            37.3346)
    }

    @Test
    @MainActor
    func callProviderMapKitEstimateTravelTimeSucceedsWithMockStore() throws {
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "ETA Source"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "ETA Destination"
        let departureDate = Date(timeIntervalSince1970: 1_718_000_000)
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.estimateTravelTimeResults = [
            MapKitEstimateTravelTimeResult(
                source: sourceItem,
                destination: destinationItem,
                expectedTravelTime: 900,
                distance: 5000,
                expectedArrivalDate: departureDate.addingTimeInterval(900),
                expectedDepartureDate: departureDate,
                transportType: .walking
            ),
        ]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "estimate_travel_time",
            payloadJson: estimateTravelTimePayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194
            )
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["expected_travel_time"] as? Double == 900)
        #expect(decoded?["distance"] as? Double == 5000)
        let transportType = decoded?["transport_type"] as? [String]
        #expect(transportType == ["walking"])
    }

    @Test
    @MainActor
    func callProviderMapKitOpenNavigationSucceedsWithMockStore() throws {
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Navigation Source"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "Navigation Destination"
        let store = MockMapKitStore()
        store.authorizationStatus = .authorized
        store.openNavigationResults = [
            MapKitOpenNavigationResult(
                source: sourceItem,
                destination: destinationItem,
                transportType: .automobile,
                directionsMode: MKLaunchOptionsDirectionsModeDriving,
                opened: true
            ),
        ]
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

        let request = ProviderRequest(
            provider: "mapkit",
            operation: "open_navigation",
            payloadJson: navigationPayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194
            )
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["opened"] as? Bool == true)
        let source = decoded?["source"] as? [String: Any]
        #expect(source?["name"] as? String == "Navigation Source")
    }

    @Test
    @MainActor
    func callProviderMapKitReturnsUnknownOperation() throws {
        let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: MockMapKitStore()))
        let request = ProviderRequest(provider: "mapkit", operation: "lookup_place", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains("lookup_place") == true)
    }

    private func calculateRoutePayload(
        sourceLatitude: Double,
        sourceLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double
    ) -> String {
        "{\"source\":{\"coordinate\":{\"latitude\":\(sourceLatitude),\"longitude\":\(sourceLongitude)}},"
            + "\"destination\":{\"coordinate\":{\"latitude\":\(destinationLatitude),"
            + "\"longitude\":\(destinationLongitude)}}}"
    }

    private func estimateTravelTimePayload(
        sourceLatitude: Double,
        sourceLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double
    ) -> String {
        calculateRoutePayload(
            sourceLatitude: sourceLatitude,
            sourceLongitude: sourceLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude
        )
    }

    private func navigationPayload(
        sourceLatitude: Double,
        sourceLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double
    ) -> String {
        calculateRoutePayload(
            sourceLatitude: sourceLatitude,
            sourceLongitude: sourceLongitude,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude
        )
    }
}

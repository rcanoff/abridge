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
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Route Source"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "Route Destination"
        let route = MapKitRouteData(
            name: "Mock Route",
            advisoryNotices: [],
            distance: 1_000,
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
            payloadJson: #"{"source":{"coordinate":{"latitude":37.3346,"longitude":-122.0090}},"destination":{"coordinate":{"latitude":37.7749,"longitude":-122.4194}}}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let routes = decoded?["routes"] as? [[String: Any]]
        #expect(routes?.first?["name"] as? String == "Mock Route")
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
}

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

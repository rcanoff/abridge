@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderSearchNearby")
struct MapKitProviderSearchNearbyTests {
    @Test
    @MainActor
    func searchNearbyReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchNearbyRequiresRegionOrCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "search_nearby", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func searchNearbyRejectsBothRegionAndCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"region":{"center":{"latitude":37.0,"longitude":-122.0},"span":{"latitude_delta":0.1,"longitude_delta":0.1}},"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func searchNearbyReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Nearby Cafe"
        let store = MockMapKitStore()
        store.nearbyResults = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0},"radius_meters":800}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Nearby Cafe")
        #expect(store.lastNearbyRequest != nil)
    }
}

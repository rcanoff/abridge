import CoreLocation
import MapKit
import Testing
@testable import AppleBridge

@Suite("MapKitProviderSearchPlaces")
struct MapKitProviderSearchPlacesTests {
    @Test
    @MainActor
    func searchPlacesReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchPlacesRequiresQuery() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "search_places", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func searchPlacesReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Mock Cafe"
        let store = MockMapKitStore()
        store.results = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Mock Cafe")
        #expect(store.lastRequest?.query == "coffee")
    }
}
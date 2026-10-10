@testable import ABridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderReverseGeocode")
struct MapKitProviderReverseGeocodeTests {
    @Test
    @MainActor
    func reverseGeocodeReturnsSerializedResponse() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        item.name = "1 Apple Park Way"
        let store = MockMapKitStore()
        store.reverseGeocodeResults = [[item]]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "reverse_geocode",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "1 Apple Park Way")
        #expect(store.lastReverseGeocodeRequest?.coordinate.latitude == 37.0)
    }
}

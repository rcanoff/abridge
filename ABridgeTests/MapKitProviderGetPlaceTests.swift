@testable import ABridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderGetPlace")
struct MapKitProviderGetPlaceTests {
    @Test
    @MainActor
    func getPlaceReturnsSerializedMapItem() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(
            latitude: 37.3346,
            longitude: -122.0090
        ))
        item.name = "Get Place Mock"
        let store = MockMapKitStore()
        store.getPlaceResults = [item]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "get_place",
            payloadJson: #"{"identifier":"I1234567890"}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["name"] as? String == "Get Place Mock")
        #expect(store.lastGetPlaceRequest?.identifier == "I1234567890")
        #expect(decoded?.keys.contains("placemark") == true)
        #expect(decoded?.keys.contains("identifier") == true)
    }
}

@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderLookupPlace")
struct MapKitProviderLookupPlaceTests {
    @Test
    @MainActor
    func lookupPlaceReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "lookup_place",
            payloadJson: #"{"identifier":"I1234567890"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func lookupPlaceRequiresIdentifier() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "lookup_place", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func lookupPlaceReturnsSerializedMapItem() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Lookup Mock Place"
        let store = MockMapKitStore()
        store.lookupPlaceResults = [item]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "lookup_place",
            payloadJson: #"{"identifier":"I1234567890"}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["name"] as? String == "Lookup Mock Place")
        #expect(store.lastLookupPlaceRequest?.identifier == "I1234567890")
        #expect(decoded?.keys.contains("placemark") == true)
        #expect(decoded?.keys.contains("identifier") == true)
    }
}

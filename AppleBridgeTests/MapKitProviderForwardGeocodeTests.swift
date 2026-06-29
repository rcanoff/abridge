@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderForwardGeocode")
struct MapKitProviderForwardGeocodeTests {
    @Test
    @MainActor
    func forwardGeocodeReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "forward_geocode",
            payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func forwardGeocodeRequiresAddress() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "forward_geocode", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func forwardGeocodeReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Apple Park"
        let store = MockMapKitStore()
        store.forwardGeocodeResults = [[item]]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "forward_geocode",
            payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Apple Park")
        #expect(store.lastForwardGeocodeRequest?.address == "1 Apple Park Way, Cupertino, CA")
    }
}
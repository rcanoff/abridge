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
    func forwardGeocodeRequiresAddress_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func forwardGeocodeReturnsSerializedResponse() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(
            latitude: 37.3346,
            longitude: -122.0090
        ))
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

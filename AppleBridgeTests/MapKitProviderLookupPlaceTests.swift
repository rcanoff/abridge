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
    func lookupPlaceRequiresIdentifier_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func lookupPlaceReturnsSerializedMapItem() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(
            latitude: 37.3346,
            longitude: -122.0090
        ))
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

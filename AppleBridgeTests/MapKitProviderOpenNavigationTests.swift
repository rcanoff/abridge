@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderOpenNavigation")
struct MapKitProviderOpenNavigationTests {
    @Test
    @MainActor
    func openNavigationReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: navigationPayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194
            )
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func openNavigationRequiresSourceAndDestination() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "open_navigation", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func openNavigationReturnsSerializedResponse() throws {
        let store = makeSerializedNavigationStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: navigationPayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194,
                transportType: "walking"
            )
        )

        try expectSerializedOpenNavigationResponse(response, store: store)
    }

    @MainActor
    private func makeSerializedNavigationStore() -> MockMapKitStore {
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Navigation Source"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "Navigation Destination"

        let store = MockMapKitStore()
        store.openNavigationResults = [
            MapKitOpenNavigationResult(
                source: sourceItem,
                destination: destinationItem,
                transportType: .walking,
                directionsMode: MKLaunchOptionsDirectionsModeWalking,
                opened: true
            ),
        ]
        return store
    }

    @MainActor
    private func expectSerializedOpenNavigationResponse(
        _ response: ProviderResponse,
        store: MockMapKitStore
    ) throws {
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["opened"] as? Bool == true)
        let source = decoded?["source"] as? [String: Any]
        let destination = decoded?["destination"] as? [String: Any]
        #expect(source?["name"] as? String == "Navigation Source")
        #expect(destination?["name"] as? String == "Navigation Destination")
        let transportType = decoded?["transport_type"] as? [String]
        #expect(transportType == ["walking"])
        let launchOptions = decoded?["launch_options"] as? [String: Any]
        #expect(launchOptions?["directions_mode"] as? String == MKLaunchOptionsDirectionsModeWalking)
        #expect(store.lastOpenNavigationRequest?.transportType == .walking)
    }

    private func navigationPayload(
        sourceLatitude: Double,
        sourceLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double,
        transportType: String? = nil
    ) -> String {
        var parts = [
            #""source":{"coordinate":{"latitude":\#(sourceLatitude),"longitude":\#(sourceLongitude)}}"#,
            #""destination":{"coordinate":{"latitude":\#(destinationLatitude),"longitude":\#(destinationLongitude)}}"#,
        ]
        if let transportType {
            parts.append(#""transport_type":"\#(transportType)""#)
        }
        return "{\(parts.joined(separator: ","))}"
    }
}
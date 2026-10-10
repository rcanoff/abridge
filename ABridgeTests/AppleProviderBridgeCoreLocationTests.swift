@testable import ABridge
import CoreLocation
import Foundation
import Testing

@Suite("AppleProviderBridgeCoreLocation")
struct AppleProviderBridgeCoreLocationTests {
    @Test @MainActor func callProviderCoreLocationGetCurrentLocationSucceedsWithMockStore() throws {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            course: -1.0,
            speed: -1.0,
            timestamp: Date(timeIntervalSince1970: 1_751_280_000)
        )
        let store = MockCoreLocationStore()
        store.authorizationStatus = .authorized
        store.getCurrentLocationResult = location
        let response = AppleProviderBridge(coreLocationProvider: CoreLocationProvider(store: store))
            .callProvider(request: ProviderRequest(
                provider: "corelocation",
                operation: "get_current_location",
                payloadJson: "{}"
            ))
        #expect(response.ok == true)
        let decoded = try JSONSerialization
            .jsonObject(with: #require(response.payloadJson.data(using: .utf8))) as? [String: Any]
        #expect(((decoded?["location"] as? [String: Any])?["coordinate"] as? [String: Any])?["latitude"] as? Double ==
            37.3346)
    }
}

@testable import ABridge
import CoreLocation
import Testing

@Suite("CoreLocationProviderGetCurrentLocation")
struct CoreLocationProviderLocationTests {
    @Test @MainActor func getCurrentLocationReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockCoreLocationStore()
        store.authorizationStatus = .denied
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("System Settings") == true)
        #expect(store.getCurrentLocationCallCount == 0)
    }

    @Test @MainActor func getCurrentLocationSaysWhenPermissionIsNotDetermined() {
        let store = MockCoreLocationStore()
        store.authorizationStatus = .notDetermined
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("not determined") == true)
        #expect(store.getCurrentLocationCallCount == 0)
    }

    @Test @MainActor func getCurrentLocationSaysWhenLocationServicesAreOff() {
        let store = MockCoreLocationStore()
        store.authorizationStatus = .authorized
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { false })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("location_services_off") == true)
        #expect(response.errorJson?.contains("System Settings") == true)
        #expect(store.getCurrentLocationCallCount == 0)
    }

    @Test @MainActor func getCurrentLocationMapsLocationUnknownToNoFix() {
        let store = MockCoreLocationStore()
        store.authorizationStatus = .authorized
        store.getCurrentLocationError = NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue)
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("location_unknown") == true)
        #expect(response.errorJson?.contains("kCLErrorDomain") == true)
        #expect(store.getCurrentLocationCallCount == 1)
    }

    @Test @MainActor func getCurrentLocationMapsTimeoutToNoFix() {
        let store = MockCoreLocationStore()
        store.authorizationStatus = .authorized
        store.getCurrentLocationError = CoreLocationProviderError.corelocationError("CoreLocation request timed out")
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("location_unknown") == true)
        #expect(response.errorJson?.contains("timed out") == true)
    }

    @Test @MainActor func getCurrentLocationReturnsSerializedResponse() throws {
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
        store.getCurrentLocationResult = location
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "{}")
        #expect(response.ok == true)
        #expect(store.getCurrentLocationCallCount == 1)
        let decoded = try JSONSerialization
            .jsonObject(with: #require(response.payloadJson.data(using: .utf8))) as? [String: Any]
        let coordinate = (decoded?["location"] as? [String: Any])?["coordinate"] as? [String: Any]
        #expect(coordinate?["latitude"] as? Double == 37.3346)
        #expect(coordinate?["longitude"] as? Double == -122.0090)
    }

    @Test @MainActor func getCurrentLocationAcceptsEmptyPayload() {
        let store = MockCoreLocationStore()
        store.getCurrentLocationResult = CLLocation(latitude: 1.0, longitude: 2.0)
        let response = CoreLocationProvider(store: store, locationServicesEnabled: { true })
            .handle(operation: "get_current_location", payloadJson: "")
        #expect(response.ok == true)
    }
}

@testable import AppleBridge
import Testing

@Suite("AppStoreLocation")
struct AppStoreLocationTests {
    @Test
    @MainActor
    func requestLocationAccessUpdatesStatus() async throws {
        let mock = MockLocationPermissionService()
        mock.requestResult = .success(.authorizedAlways)
        let store = AppStore(locationPermissionService: mock)

        await store.requestLocationAccess()

        #expect(store.locationPermissionStatus == .authorizedAlways)
        #expect(mock.requestCallCount == 1)
    }

    @Test
    @MainActor
    func requestLocationAccessSurfacesError() async {
        let mock = MockLocationPermissionService()
        mock.requestResult = .failure(LocationPermissionError.requestFailed("denied"))
        let store = AppStore(locationPermissionService: mock)

        await store.requestLocationAccess()

        #expect(store.lastError == "denied")
    }
}
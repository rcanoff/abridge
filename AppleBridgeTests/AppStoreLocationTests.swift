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
        #expect(store.isRequestingLocationPermission == false)
    }

    @Test
    @MainActor
    func requestLocationAccessTogglesLoadingState() async {
        let mock = BlockingLocationPermissionService()
        let store = AppStore(locationPermissionService: mock)

        let task = Task { await store.requestLocationAccess() }
        await Task.yield()

        #expect(store.isRequestingLocationPermission == true)

        mock.resume(with: .success(.authorized))
        await task.value

        #expect(store.isRequestingLocationPermission == false)
    }

    @Test
    @MainActor
    func requestLocationAccessClearsLoadingStateOnTimeout() async {
        let mock = MockLocationPermissionService()
        mock.requestResult = .failure(
            LocationPermissionError.requestFailed("Location authorization request timed out.")
        )
        let store = AppStore(locationPermissionService: mock)

        await store.requestLocationAccess()

        #expect(store.lastError == "Location authorization request timed out.")
        #expect(store.isRequestingLocationPermission == false)
    }
}
@testable import AppleBridge
import CoreLocation
import Foundation
import Testing

@Suite("LiveMapKitStoreGetCurrentLocation")
struct LiveMapKitStoreGetCurrentLocationTests {
    @Test
    @MainActor
    func getCurrentLocationPumpsRunLoopForDeferredFetcherCallback() throws {
        let fetcher = DeferredLocationFetcher()
        var store = LiveMapKitStore()
        store.makeLocationFetcher = { fetcher }

        let expected = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            timestamp: Date(timeIntervalSince1970: 1_751_280_000)
        )
        fetcher.deferredOutcome = .success(expected)

        let location = try store.getCurrentLocation()
        #expect(location.coordinate.latitude == 37.3346)
        #expect(location.coordinate.longitude == -122.0090)
        #expect(fetcher.requestCount == 1)
    }

    @Test
    @MainActor
    func getCurrentLocationPropagatesFetcherFailure() {
        let fetcher = DeferredLocationFetcher()
        var store = LiveMapKitStore()
        store.makeLocationFetcher = { fetcher }

        let expectedError = MapKitProviderError.mapkitError("simulated location failure")
        fetcher.deferredOutcome = .failure(expectedError)

        #expect(throws: expectedError) {
            try store.getCurrentLocation()
        }
        #expect(fetcher.requestCount == 1)
    }

    @Test
    @MainActor
    func getCurrentLocationTimesOutWhenFetcherNeverCompletes() {
        let fetcher = DeferredLocationFetcher()
        var store = LiveMapKitStore()
        store.makeLocationFetcher = { fetcher }
        store.locationFetchTimeout = 0.1

        let started = ContinuousClock.now

        #expect(throws: MapKitProviderError.mapkitError("CoreLocation request timed out")) {
            try store.getCurrentLocation()
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(store.locationFetchTimeout + 0.25))
        #expect(fetcher.requestCount == 1)
    }
}

@MainActor
private final class DeferredLocationFetcher: MapKitLocationFetching {
    var deferredOutcome: Result<CLLocation, Error>?
    private(set) var requestCount = 0

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        requestCount += 1
        guard deferredOutcome != nil else { return }

        Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { _ in
            if let deferredOutcome = self.deferredOutcome {
                completion(deferredOutcome)
            }
        }
    }
}

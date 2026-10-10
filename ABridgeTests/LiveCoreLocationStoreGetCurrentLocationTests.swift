@testable import ABridge
import CoreLocation
import Foundation
import Testing

@Suite("LiveCoreLocationStoreGetCurrentLocation")
struct LiveCoreLocationStoreLocationTests {
    @Test
    @MainActor
    func getCurrentLocationPumpsRunLoopForDeferredFetcherCallback() throws {
        let fetcher = DeferredLocationFetcher()
        var store = LiveCoreLocationStore()
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
        var store = LiveCoreLocationStore()
        store.makeLocationFetcher = { fetcher }

        let expectedError = CoreLocationProviderError.corelocationError("simulated location failure")
        fetcher.deferredOutcome = .failure(expectedError)

        #expect(throws: expectedError) {
            try store.getCurrentLocation()
        }
        #expect(fetcher.requestCount == 1)
    }

    @Test
    @MainActor
    func getCurrentLocationUsesDefaultOneShotLocationFetcherFactory() {
        let store = LiveCoreLocationStore()
        #expect(store.makeLocationFetcher() is OneShotLocationFetcher)
    }

    @Test
    @MainActor
    func getCurrentLocationPumpsRunLoopForProductionOneShotFetcherDelegateCallback() throws {
        let manager = SimulatedLocationManager()
        let expected = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            timestamp: Date(timeIntervalSince1970: 1_751_280_000)
        )
        manager.deferredOutcome = .success(expected)

        weak var weakFetcher: OneShotLocationFetcher?
        var store = LiveCoreLocationStore()
        store.makeLocationFetcher = {
            let fetcher = OneShotLocationFetcher(locationManager: manager)
            weakFetcher = fetcher
            manager.fetcherAliveAtRequest = { weakFetcher != nil }
            return fetcher
        }

        let location = try store.getCurrentLocation()
        #expect(location.coordinate.latitude == 37.3346)
        #expect(location.coordinate.longitude == -122.0090)
        #expect(manager.requestCount == 1)
        #expect(manager.fetcherWasAliveWhenRequested == true)
        #expect(manager.fetcherWasAliveAtDelegateDelivery == true)
    }

    @Test
    @MainActor
    func getCurrentLocationPropagatesProductionOneShotFetcherDelegateFailure() {
        let manager = SimulatedLocationManager()
        let expectedError = CoreLocationProviderError.corelocationError("simulated one-shot location failure")
        manager.deferredOutcome = .failure(expectedError)

        var store = LiveCoreLocationStore()
        store.makeLocationFetcher = {
            OneShotLocationFetcher(locationManager: manager)
        }

        #expect(throws: expectedError) {
            try store.getCurrentLocation()
        }
        #expect(manager.requestCount == 1)
    }

    @Test
    @MainActor
    func getCurrentLocationTimesOutWhenFetcherNeverCompletes() {
        let fetcher = DeferredLocationFetcher()
        var store = LiveCoreLocationStore()
        store.makeLocationFetcher = { fetcher }
        store.locationFetchTimeout = 0.1

        let started = ContinuousClock.now

        #expect(throws: CoreLocationProviderError.corelocationError("CoreLocation request timed out")) {
            try store.getCurrentLocation()
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(store.locationFetchTimeout + 0.25))
        #expect(fetcher.requestCount == 1)
    }
}

private final class SimulatedLocationManager: CoreLocationManaging, @unchecked Sendable {
    weak var delegate: CLLocationManagerDelegate?
    var deferredOutcome: Result<CLLocation, Error>?
    var fetcherAliveAtRequest: (() -> Bool)?
    private(set) var requestCount = 0
    private(set) var fetcherWasAliveWhenRequested = false
    private(set) var fetcherWasAliveAtDelegateDelivery = false

    func requestLocation() {
        requestCount += 1
        fetcherWasAliveWhenRequested = fetcherAliveAtRequest?() ?? false
        guard let deferredOutcome else { return }
        scheduleDelegateDelivery(deferredOutcome)
    }

    private func scheduleDelegateDelivery(_ outcome: Result<CLLocation, Error>) {
        Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { [weak self] _ in
            self?.deliverDelegateOutcome(outcome)
        }
    }

    private func deliverDelegateOutcome(_ outcome: Result<CLLocation, Error>) {
        guard let delegate else { return }
        fetcherWasAliveAtDelegateDelivery = fetcherAliveAtRequest?() ?? false
        let manager = CLLocationManager()

        switch outcome {
        case let .success(location):
            delegate.locationManager?(manager, didUpdateLocations: [location])
        case let .failure(error):
            delegate.locationManager?(manager, didFailWithError: error)
        }
    }
}

private final class DeferredLocationFetcher: CoreLocationFetching, @unchecked Sendable {
    var deferredOutcome: Result<CLLocation, Error>?
    private(set) var requestCount = 0

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        requestCount += 1
        guard let deferredOutcome else { return }

        Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { _ in
            completion(deferredOutcome)
        }
    }
}

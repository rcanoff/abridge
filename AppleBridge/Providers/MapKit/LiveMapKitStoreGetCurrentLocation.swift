import CoreLocation
import Foundation

@MainActor
protocol MapKitLocationFetching: AnyObject {
    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void)
}

extension LiveMapKitStore {
    func getCurrentLocation() throws -> CLLocation {
        let result = MapKitSearchFetch.AsyncBridgeResult<CLLocation>()
        let retention = LocationFetcherRetentionBox()

        try waitForCurrentLocationCompletion(retention: retention) { complete in
            let fetcher = makeLocationFetcher()
            retention.setFetcher(fetcher)
            fetcher.requestLocation { outcome in
                retention.setFetcher(nil)
                switch outcome {
                case let .success(value): result.setValue(value)
                case let .failure(error): result.setError(error)
                }
                complete()
            }
        }
        return try result.get()
    }

    private func waitForCurrentLocationCompletion(
        retention: LocationFetcherRetentionBox,
        work: (@escaping () -> Void) -> Void
    ) throws {
        var done = false
        work {
            done = true
        }

        let deadline = Date().addingTimeInterval(locationFetchTimeout)
        while !done, Date() < deadline {
            retention.keepAliveDuringPump()
            MapKitSearchFetch.pumpRunLoop(for: MapKitSearchFetch.runLoopInterval)
        }

        guard done else {
            throw MapKitProviderError.mapkitError("CoreLocation request timed out")
        }
    }
}

final class LocationFetcherRetentionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fetcher: AnyObject?

    func setFetcher(_ fetcher: AnyObject?) {
        lock.lock()
        defer { lock.unlock() }
        self.fetcher = fetcher
    }

    func keepAliveDuringPump() {
        lock.lock()
        defer { lock.unlock() }
        _ = fetcher
    }
}

@MainActor
final class OneShotLocationFetcher: NSObject, MapKitLocationFetching, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?
    override init() {
        super.init(); manager.delegate = self
    }

    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        self.completion = completion; manager.requestLocation()
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let completion else { return }; self.completion = nil
        if let location = locations.last {
            completion(.success(location))
        } else {
            completion(.failure(MapKitProviderError.mapkitError("CoreLocation returned no location")))
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard let completion else { return }; self.completion = nil; completion(.failure(error))
    }
}
import CoreLocation
import Foundation

protocol MapKitLocationFetching: AnyObject {
    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void)
}

protocol MapKitLocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    func requestLocation()
}

extension CLLocationManager: MapKitLocationManaging {}

extension LiveMapKitStore {
    func getCurrentLocation() throws -> CLLocation {
        let result = MapKitSearchFetch.AsyncBridgeResult<CLLocation>()
        let retention = LocationFetcherRetentionBox()

        try MapKitSearchFetch.waitForCompletion(
            operation: "CoreLocation request",
            timeout: locationFetchTimeout
        ) { complete in
            let fetcher = makeLocationFetcher()
            retention.setFetcher(fetcher)
            retention.keepAliveDuringPump()
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

final class OneShotLocationFetcher: NSObject, MapKitLocationFetching, CLLocationManagerDelegate {
    private let manager: any MapKitLocationManaging
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    init(locationManager: any MapKitLocationManaging = CLLocationManager()) {
        manager = locationManager
        super.init()
        manager.delegate = self
    }

    /// Callers must invoke on the main queue (`waitForCompletion` schedules work there).
    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void) {
        assert(Thread.isMainThread, "OneShotLocationFetcher.requestLocation requires main thread")
        self.completion = completion
        manager.requestLocation()
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let completion else { return }
        self.completion = nil
        if let location = locations.last {
            completion(.success(location))
        } else {
            completion(.failure(MapKitProviderError.mapkitError("CoreLocation returned no location")))
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard let completion else { return }
        self.completion = nil
        completion(.failure(error))
    }
}

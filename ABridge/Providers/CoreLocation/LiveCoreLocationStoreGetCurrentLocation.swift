import CoreLocation
import Foundation

protocol CoreLocationFetching: AnyObject {
    func requestLocation(completion: @escaping (Result<CLLocation, Error>) -> Void)
}

protocol CoreLocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    func requestLocation()
}

extension CLLocationManager: CoreLocationManaging {}

extension LiveCoreLocationStore {
    func getCurrentLocation() throws -> CLLocation {
        let result = CoreLocationFetch.AsyncBridgeResult<CLLocation>()
        let retention = LocationFetcherRetentionBox()

        try CoreLocationFetch.waitForCompletion(
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

final class OneShotLocationFetcher: NSObject, CoreLocationFetching, CLLocationManagerDelegate {
    private let manager: any CoreLocationManaging
    private var completion: ((Result<CLLocation, Error>) -> Void)?

    init(locationManager: any CoreLocationManaging = CLLocationManager()) {
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
            completion(.failure(CoreLocationProviderError.corelocationError("CoreLocation returned no location")))
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard let completion else { return }
        self.completion = nil
        completion(.failure(error))
    }
}

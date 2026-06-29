import CoreLocation
import Foundation

extension LiveMapKitStore {
    func getCurrentLocation() throws -> CLLocation {
        let result = MapKitSearchFetch.AsyncBridgeResult<CLLocation>()
        var fetchHolder: OneShotLocationFetcher?
        do {
            try MapKitSearchFetch.waitForCompletion { complete in
                // Schedule via GCD so run-loop pumping can deliver delegate callbacks while this
                // @MainActor method blocks synchronously.
                DispatchQueue.main.async {
                    let fetcher = OneShotLocationFetcher()
                    fetchHolder = fetcher
                    fetcher.requestLocation { outcome in
                        fetchHolder = nil
                        switch outcome {
                        case let .success(value): result.setValue(value)
                        case let .failure(error): result.setError(error)
                        }
                        complete()
                    }
                }
            }
        } catch let error as MapKitProviderError {
            if case let .mapkitError(message) = error, message == "MapKit search timed out" {
                throw MapKitProviderError.mapkitError("CoreLocation request timed out")
            }
            throw error
        }
        return try result.get()
    }
}

@MainActor
private final class OneShotLocationFetcher: NSObject, @preconcurrency CLLocationManagerDelegate {
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

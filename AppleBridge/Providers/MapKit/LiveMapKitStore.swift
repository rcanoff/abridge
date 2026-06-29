import CoreLocation
import Foundation
import MapKit

@MainActor
enum MapKitSearchFetch {
    /// Upper bound for blocking the main actor while MapKit delivers its callback.
    static let defaultTimeout: TimeInterval = 30
    static let runLoopInterval: TimeInterval = 0.01

    /// Thread-safe handoff for sync/async CoreLocation bridges that schedule delegate callbacks.
    final class AsyncBridgeResult<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        private var error: Error?

        func setValue(_ value: T) {
            lock.lock()
            defer { lock.unlock() }
            self.value = value
        }

        func setError(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            self.error = error
        }

        func get() throws -> T {
            lock.lock()
            defer { lock.unlock() }
            if let error {
                throw error
            }
            guard let value else {
                throw MapKitProviderError.mapkitError("MapKit async bridge returned no result")
            }
            return value
        }
    }

    static func waitForCompletion(
        timeout: TimeInterval = defaultTimeout,
        work: (@escaping () -> Void) -> Void
    ) throws {
        var done = false
        work {
            done = true
        }

        // MapKit delivers the completion on the main run loop. Pump explicitly on `.main`
        // (not `.current`) so this stays correct when called via `DispatchQueue.main.sync`.
        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            EventKitReminderFetch.pumpRunLoop(until: Date(timeIntervalSinceNow: runLoopInterval))
        }

        guard done else {
            throw MapKitProviderError.mapkitError("MapKit search timed out")
        }
    }
}

@MainActor
struct LiveMapKitStore: MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        let mkRequest = MKLocalSearch.Request()
        mkRequest.naturalLanguageQuery = request.query
        if let region = request.region {
            mkRequest.region = region
        }
        mkRequest.regionPriority = request.regionPriority
        if let resultTypes = request.resultTypes {
            mkRequest.resultTypes = resultTypes
        }

        let search = MKLocalSearch(request: mkRequest)
        var response: MKLocalSearch.Response?
        var searchError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            search.start { result, error in
                response = result
                searchError = error
                complete()
            }
        }

        if let searchError {
            throw searchError
        }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit search returned no response")
        }
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
        let mkRequest = MKLocalSearch.Request()
        mkRequest.region = request.region
        mkRequest.regionPriority = .required
        mkRequest.resultTypes = .pointOfInterest
        mkRequest.pointOfInterestFilter = request.pointOfInterestFilter

        let search = MKLocalSearch(request: mkRequest)
        var response: MKLocalSearch.Response?
        var searchError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            search.start { result, error in
                response = result
                searchError = error
                complete()
            }
        }

        if let searchError {
            throw searchError
        }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit search returned no response")
        }
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
        // macOS 26 SDK: MKReverseGeocodingRequest exposes only init(location:), not init(coordinate:).
        let location = CLLocation(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude
        )
        guard let mkRequest = MKReverseGeocodingRequest(location: location) else {
            throw MapKitProviderError.mapkitError("MapKit reverse geocode request could not be created")
        }
        var mapItems: [MKMapItem]?
        var geocodeError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            Task { @MainActor in
                defer { complete() }
                do {
                    mapItems = try await mkRequest.mapItems
                } catch {
                    geocodeError = error
                }
            }
        }

        if let geocodeError {
            throw geocodeError
        }
        guard let mapItems else {
            throw MapKitProviderError.mapkitError("MapKit reverse geocode returned no response")
        }
        return mapItems
    }

    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
        guard let mkRequest = MKGeocodingRequest(addressString: request.address) else {
            throw MapKitProviderError.mapkitError("MapKit forward geocode request could not be created")
        }
        if let region = request.region {
            mkRequest.region = region
        }
        if let preferredLocale = request.preferredLocale {
            mkRequest.preferredLocale = preferredLocale
        }
        var mapItems: [MKMapItem]?
        var geocodeError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            Task { @MainActor in
                defer { complete() }
                do {
                    mapItems = try await mkRequest.mapItems
                } catch {
                    geocodeError = error
                }
            }
        }

        if let geocodeError {
            throw geocodeError
        }
        guard let mapItems else {
            throw MapKitProviderError.mapkitError("MapKit forward geocode returned no response")
        }
        return mapItems
    }

    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult {
        let mkRequest = MKDirections.Request()
        mkRequest.source = mapItem(for: request.source.coordinate)
        mkRequest.destination = mapItem(for: request.destination.coordinate)
        mkRequest.transportType = request.transportType
        mkRequest.requestsAlternateRoutes = request.requestsAlternateRoutes
        mkRequest.departureDate = request.departureDate
        mkRequest.arrivalDate = request.arrivalDate
        mkRequest.tollPreference = request.tollPreference
        mkRequest.highwayPreference = request.highwayPreference

        let directions = MKDirections(request: mkRequest)
        var response: MKDirections.Response?
        var directionsError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            Task { @MainActor in
                defer { complete() }
                do {
                    response = try await directions.calculate()
                } catch {
                    directionsError = error
                }
            }
        }

        if let directionsError {
            throw directionsError
        }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit directions returned no response")
        }

        return MapKitCalculateRouteResult(
            source: response.source,
            destination: response.destination,
            routes: response.routes.map(Self.routeData(from:))
        )
    }

    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult {
        let mkRequest = MKDirections.Request()
        mkRequest.source = mapItem(for: request.source.coordinate)
        mkRequest.destination = mapItem(for: request.destination.coordinate)
        mkRequest.transportType = request.transportType
        mkRequest.departureDate = request.departureDate
        mkRequest.arrivalDate = request.arrivalDate

        let directions = MKDirections(request: mkRequest)
        var response: MKDirections.ETAResponse?
        var directionsError: Error?

        try MapKitSearchFetch.waitForCompletion { complete in
            Task { @MainActor in
                defer { complete() }
                do {
                    response = try await directions.calculateETA()
                } catch {
                    directionsError = error
                }
            }
        }

        if let directionsError {
            throw directionsError
        }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit ETA returned no response")
        }

        return MapKitEstimateTravelTimeResult(
            source: response.source,
            destination: response.destination,
            expectedTravelTime: response.expectedTravelTime,
            distance: response.distance,
            expectedArrivalDate: response.expectedArrivalDate,
            expectedDepartureDate: response.expectedDepartureDate,
            transportType: response.transportType
        )
    }

    private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }

    private static func routeData(from route: MKRoute) -> MapKitRouteData {
        MapKitRouteData(
            name: route.name,
            advisoryNotices: route.advisoryNotices,
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            transportType: route.transportType,
            polylineCoordinates: coordinates(from: route.polyline),
            polylineTitle: route.polyline.title,
            polylineSubtitle: route.polyline.subtitle,
            steps: route.steps.map(stepData(from:)),
            hasTolls: route.hasTolls,
            hasHighways: route.hasHighways
        )
    }

    private static func stepData(from step: MKRoute.Step) -> MapKitRouteStepData {
        MapKitRouteStepData(
            instructions: step.instructions,
            notice: step.notice,
            distance: step.distance,
            transportType: step.transportType,
            polylineCoordinates: coordinates(from: step.polyline),
            polylineTitle: step.polyline.title,
            polylineSubtitle: step.polyline.subtitle
        )
    }

    private static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }

        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }

    func getCurrentLocation() throws -> CLLocation {
        let result = MapKitSearchFetch.AsyncBridgeResult<CLLocation>()
        do {
            try MapKitSearchFetch.waitForCompletion { complete in
                // Schedule via GCD so run-loop pumping can deliver delegate callbacks while this
                // @MainActor method blocks synchronously.
                DispatchQueue.main.async {
                    let fetcher = OneShotLocationFetcher()
                    fetcher.requestLocation { outcome in
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
        if let location = locations.last { completion(.success(location)) }
        else { completion(.failure(MapKitProviderError.mapkitError("CoreLocation returned no location"))) }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard let completion else { return }; self.completion = nil; completion(.failure(error))
    }
}

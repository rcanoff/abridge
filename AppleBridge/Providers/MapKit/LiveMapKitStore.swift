import CoreLocation
import Foundation
@preconcurrency import MapKit

/// Sync bridge helpers for MapKit/CoreLocation under the UniFFI sync FFI.
///
/// **Critical:** MapKit network APIs do not deliver completions while a main-queue item is blocked
/// (including `DispatchQueue.main.sync` + `RunLoop` pumping). Start work on the main queue, then
/// wait on a **background** thread so the main run loop stays free.
enum MapKitSearchFetch {
    /// Upper bound while waiting for MapKit / CoreLocation to finish.
    static let defaultTimeout: TimeInterval = 30

    /// Modes pumped for main-thread waiters (unit tests / rare main callers).
    static let runLoopModes: [RunLoop.Mode] = [.default, .common, .eventTracking]

    static let runLoopInterval: TimeInterval = 0.01

    /// Thread-safe handoff for sync/async MapKit and CoreLocation bridges.
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

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func fire(_ semaphore: DispatchSemaphore) {
            lock.lock()
            defer { lock.unlock() }
            guard !fired else { return }
            fired = true
            semaphore.signal()
        }

        var hasFired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }
    }

    /// Starts `work` on the main queue (it must schedule MapKit and return quickly), then waits
    /// until `complete` is called.
    ///
    /// - Off main (production FFI): `DispatchQueue.main.async` + semaphore wait on this thread.
    /// - On main (tests): enqueue `work`, then pump the run loop until done or timeout.
    static func waitForCompletion(
        operation: String,
        timeout: TimeInterval = defaultTimeout,
        work: @escaping (@escaping @Sendable () -> Void) -> Void
    ) throws {
        // MapKit request types are non-Sendable; this bridge is single-flight per call.
        nonisolated(unsafe) let startWork = work

        if Thread.isMainThread {
            // Unit tests only (production MapKit FFI is always off-main). Start work inline
            // and pump so Timer / CoreLocation test seams fire. Prefer run-loop sources over
            // bare `Task` in main-thread tests — Task may not progress under this pump.
            let semaphore = DispatchSemaphore(value: 0)
            let once = OnceFlag()
            let complete: @Sendable () -> Void = { once.fire(semaphore) }
            startWork(complete)
            let deadline = Date().addingTimeInterval(timeout)
            while !once.hasFired, Date() < deadline {
                pumpRunLoop(for: runLoopInterval)
            }
            guard once.hasFired else {
                throw MapKitProviderError.mapkitError("\(operation) timed out")
            }
            return
        }

        try waitOffMain(operation: operation, timeout: timeout, startWork: startWork)
    }

    /// Start MapKit on the main queue; wait on the calling (background) thread.
    private static func waitOffMain(
        operation: String,
        timeout: TimeInterval,
        startWork: @escaping (@escaping @Sendable () -> Void) -> Void
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let once = OnceFlag()
        let complete: @Sendable () -> Void = { once.fire(semaphore) }
        nonisolated(unsafe) let startWork = startWork

        DispatchQueue.main.async {
            startWork(complete)
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            throw MapKitProviderError.mapkitError("\(operation) timed out")
        }
    }

    static func pumpRunLoop(for interval: TimeInterval) {
        let perModeInterval = interval / Double(runLoopModes.count)
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: perModeInterval))
        }
    }
}

struct LiveMapKitStore: MapKitStoreing, @unchecked Sendable {
    /// Test seam; not `@Sendable` so unit tests can inject MainActor fetcher mocks.
    var makeLocationFetcher: () -> any MapKitLocationFetching = { OneShotLocationFetcher() }
    var locationFetchTimeout: TimeInterval = MapKitSearchFetch.defaultTimeout

    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        LiveLocationAuthorization.authorizationStatusFromAnyThread()
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
        let result = MapKitSearchFetch.AsyncBridgeResult<MKLocalSearch.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit search") { complete in
            search.start { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit search returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
        // `MKLocalSearch.Request` with only `resultTypes = .pointOfInterest` and no
        // `naturalLanguageQuery` always fails with MKErrorDomain code 4 (placemark not found).
        // Nearby POI discovery without a text query must use `MKLocalPointsOfInterestRequest`.
        let poiRequest = MKLocalPointsOfInterestRequest(coordinateRegion: request.region)
        poiRequest.pointOfInterestFilter = request.pointOfInterestFilter ?? .includingAll

        let search = MKLocalSearch(request: poiRequest)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKLocalSearch.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit nearby search") { complete in
            search.start { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit search returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
        let location = CLLocation(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude
        )
        guard let mkRequest = MKReverseGeocodingRequest(location: location) else {
            throw MapKitProviderError.mapkitError("MapKit reverse geocode request could not be created")
        }
        let result = MapKitSearchFetch.AsyncBridgeResult<[MKMapItem]>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit reverse geocode") { complete in
            // Detached so a main-thread waiter is not blocked behind MainActor Task scheduling.
            Task.detached {
                defer { complete() }
                do {
                    let mapItems = try await mkRequest.mapItems
                    result.setValue(mapItems)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
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
        let result = MapKitSearchFetch.AsyncBridgeResult<[MKMapItem]>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit forward geocode") { complete in
            Task.detached {
                defer { complete() }
                do {
                    let mapItems = try await mkRequest.mapItems
                    result.setValue(mapItems)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
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
        let result = MapKitSearchFetch.AsyncBridgeResult<MKDirections.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit directions") { complete in
            directions.calculate { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit directions returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
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
        let result = MapKitSearchFetch.AsyncBridgeResult<MKDirections.ETAResponse>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit ETA") { complete in
            directions.calculateETA { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit ETA returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
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

    func lookupPlace(request: MapKitLookupPlaceRequest) throws -> MKMapItem {
        guard let identifier = MKMapItem.Identifier(rawValue: request.identifier) else {
            throw MapKitProviderError.invalidArguments("identifier is not a valid MapKit place identifier")
        }

        let mkRequest = MKMapItemRequest(mapItemIdentifier: identifier)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKMapItem>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit place lookup") { complete in
            Task.detached {
                defer { complete() }
                do {
                    let mapItem = try await mkRequest.mapItem
                    result.setValue(mapItem)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
    }

    func openNavigation(request: MapKitOpenNavigationRequest) throws -> MapKitOpenNavigationResult {
        let source = mapItem(for: request.source.coordinate)
        let destination = mapItem(for: request.destination.coordinate)
        let launchOptions = Self.launchOptions(for: request.transportType)
        let opened = MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: launchOptions
        )
        guard opened else {
            throw MapKitProviderError.mapkitError("Failed to open Apple Maps navigation")
        }

        return MapKitOpenNavigationResult(
            source: source,
            destination: destination,
            transportType: request.transportType,
            directionsMode: Self.directionsModeValue(for: request.transportType),
            opened: true
        )
    }

    private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }
}

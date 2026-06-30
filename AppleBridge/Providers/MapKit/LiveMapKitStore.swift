import CoreLocation
import Foundation
import MapKit

@MainActor
enum MapKitSearchFetch {
    /// Upper bound for blocking the main actor while MapKit delivers its callback.
    static let defaultTimeout: TimeInterval = 30

    /// Modes pumped while waiting so MapKit callbacks and user-input sources stay serviced.
    static let runLoopModes: [RunLoop.Mode] = [.default, .eventTracking]

    static let runLoopInterval: TimeInterval = 0.01

    /// Thread-safe handoff for sync/async MapKit and CoreLocation bridges that schedule callbacks or tasks.
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
        operation: String,
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
            pumpRunLoop(for: runLoopInterval)
        }

        guard done else {
            throw MapKitProviderError.mapkitError("\(operation) timed out")
        }
    }

    /// Pump common run loop modes so MapKit completions and UI events can fire during sync FFI waits.
    static func pumpRunLoop(for interval: TimeInterval) {
        let perModeInterval = interval / Double(runLoopModes.count)
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: perModeInterval))
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit search") { complete in
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit nearby search") { complete in
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit reverse geocode") { complete in
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit forward geocode") { complete in
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit directions") { complete in
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

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit ETA") { complete in
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

    func lookupPlace(request: MapKitLookupPlaceRequest) throws -> MKMapItem {
        guard let identifier = MKMapItem.Identifier(rawValue: request.identifier) else {
            throw MapKitProviderError.invalidArguments("identifier is not a valid MapKit place identifier")
        }

        let mkRequest = MKMapItemRequest(mapItemIdentifier: identifier)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKMapItem>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit place lookup") { complete in
            // Schedule via GCD so run-loop pumping can deliver work while this @MainActor
            // method blocks synchronously (Task { @MainActor } alone can deadlock here).
            DispatchQueue.main.async {
                Task {
                    defer { complete() }
                    do {
                        try await result.setValue(mkRequest.mapItem)
                    } catch {
                        result.setError(error)
                    }
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

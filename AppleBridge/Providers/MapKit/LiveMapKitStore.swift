import CoreLocation
import Foundation
import MapKit

@MainActor
enum MapKitSearchFetch {
    /// Upper bound for blocking the main actor while MapKit delivers its callback.
    static let defaultTimeout: TimeInterval = 30
    static let runLoopInterval: TimeInterval = 0.01

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
}

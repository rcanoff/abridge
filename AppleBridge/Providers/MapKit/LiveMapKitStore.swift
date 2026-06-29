import CoreLocation
import Foundation
import MapKit

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
        let finished = NSCondition()

        search.start { result, error in
            response = result
            searchError = error
            finished.lock()
            finished.signal()
            finished.unlock()
        }

        finished.lock()
        let deadline = Date().addingTimeInterval(30)
        while response == nil, searchError == nil, Date() < deadline {
            finished.wait(until: Date(timeIntervalSinceNow: 0.05))
            EventKitReminderFetch.pumpRunLoop(until: Date(timeIntervalSinceNow: 0.05))
        }
        finished.unlock()

        if let searchError {
            throw searchError
        }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit search timed out")
        }
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }
}
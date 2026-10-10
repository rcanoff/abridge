import CoreLocation
import Foundation

typealias CoreLocationFetch = MainQueueCallbackWait<CoreLocationProviderError>

struct LiveCoreLocationStore: CoreLocationStoreing, @unchecked Sendable {
    /// Test seam; not `@Sendable` so unit tests can inject MainActor fetcher mocks.
    var makeLocationFetcher: () -> any CoreLocationFetching = { OneShotLocationFetcher() }
    var locationFetchTimeout: TimeInterval = CoreLocationFetch.defaultTimeout

    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        LiveLocationAuthorization.authorizationStatusFromAnyThread()
    }
}

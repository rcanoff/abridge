import Foundation
@testable import AppleBridge

@MainActor
final class MockURLOpener: URLOpening {
    var shouldSucceed = true
    private(set) var openedURL: URL?

    func open(_ url: URL) -> Bool {
        openedURL = url
        return shouldSucceed
    }
}
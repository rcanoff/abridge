@testable import AppleBridge
import Foundation

@MainActor
final class MockAppQuitter: AppQuitting {
    private(set) var terminateCallCount = 0

    func terminate() {
        terminateCallCount += 1
    }
}

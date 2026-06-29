@testable import AppleBridge
import Foundation

final class MockAppleBridgeAppStoreMaker: AppleBridgeAppStoreMaking, @unchecked Sendable {
    private(set) var makeStoresCallCount = 0

    @MainActor
    func makeStores() -> AppleBridgeAppBootstrap.Stores {
        makeStoresCallCount += 1
        return ProductionAppleBridgeAppStoreMaker().makeStores()
    }
}
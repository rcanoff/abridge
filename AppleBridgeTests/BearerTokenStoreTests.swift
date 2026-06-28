@testable import AppleBridge
import Foundation
import Testing

@Suite("BearerTokenStore")
struct BearerTokenStoreTests {
    @Test
    func loadOrCreateCreatesAndPersistsToken() throws {
        let store = MockBearerTokenStore()

        let first = try store.loadOrCreateBearerToken()
        #expect(!first.isEmpty)

        let second = try store.loadOrCreateBearerToken()
        #expect(first == second)
    }

    @Test
    func loadOrCreateReturnsExistingToken() throws {
        let store = MockBearerTokenStore(storedToken: "existing-token")

        #expect(try store.loadOrCreateBearerToken() == "existing-token")
    }

    @Test
    func rotateBearerTokenReplacesStoredToken() throws {
        let store = MockBearerTokenStore(storedToken: "original-token")

        let rotated = try store.rotateBearerToken()

        #expect(rotated != "original-token")
        #expect(!rotated.isEmpty)
        #expect(try store.loadOrCreateBearerToken() == rotated)
    }
}

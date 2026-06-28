@testable import AppleBridge
import Foundation
import Testing

@Suite("BearerTokenStore")
struct BearerTokenStoreTests {
    @Test
    func loadOrCreateCreatesAndPersistsToken() throws {
        let store = MockBearerTokenStore()

        let first = try store.loadOrCreateBearerToken()
        #expect(first.hasPrefix(APIKeyFormatting.livePrefix))

        let second = try store.loadOrCreateBearerToken()
        #expect(first == second)
    }

    @Test
    func loadOrCreateReturnsExistingToken() throws {
        let legacyToken = "existing-token"
        let store = MockBearerTokenStore(storedToken: legacyToken)

        let loaded = try store.loadOrCreateBearerToken()
        #expect(loaded == legacyToken)
        #expect(APIKeyFormatting.isLegacyKey(loaded))
    }

    @Test
    func rotateBearerTokenReplacesStoredToken() throws {
        let store = MockBearerTokenStore(storedToken: "original-token")

        let rotated = try store.rotateBearerToken()

        #expect(rotated != "original-token")
        #expect(rotated.hasPrefix(APIKeyFormatting.livePrefix))
        #expect(try store.loadOrCreateBearerToken() == rotated)
    }
}

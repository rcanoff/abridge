@testable import AppleBridge
import Foundation
import Testing

@Suite("KeychainService")
struct KeychainServiceTests {
    private func makeService() -> KeychainService {
        let suffix = UUID().uuidString
        return KeychainService(
            service: "com.applebridge.AppleBridge.tests.\(suffix)",
            account: "bearer-token"
        )
    }

    @Test
    func loadOrCreateCreatesAndPersistsToken() throws {
        let service = makeService()
        try service.deleteBearerToken()

        let first = try service.loadOrCreateBearerToken()
        #expect(!first.isEmpty)

        let second = try service.loadOrCreateBearerToken()
        #expect(first == second)

        try service.deleteBearerToken()
    }

    @Test
    func loadBearerTokenReturnsNilWhenMissing() throws {
        let service = makeService()
        try service.deleteBearerToken()

        #expect(try service.loadBearerToken() == nil)

        try service.deleteBearerToken()
    }

    @Test
    func saveBearerTokenRoundTrips() throws {
        let service = makeService()
        try service.deleteBearerToken()

        try service.saveBearerToken("round-trip-token")
        let loaded = try service.loadBearerToken()

        #expect(loaded == "round-trip-token")

        try service.deleteBearerToken()
    }
}

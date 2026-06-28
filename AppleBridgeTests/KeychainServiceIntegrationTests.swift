@testable import AppleBridge
import Foundation
import Testing

/// Live Keychain smoke tests for `KeychainService`.
///
/// Disabled in CI and default `just test-swift` runs to avoid macOS Keychain prompts
/// from the test bundle's separate code identity. Enable locally when validating
/// production token persistence (load, save, delete, rotate).
@Suite(
    "KeychainService integration",
    .disabled("Touches live Keychain — manual smoke only")
)
struct KeychainServiceIntegrationTests {
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

    @Test
    func rotateBearerTokenReplacesStoredToken() throws {
        let service = makeService()
        try service.deleteBearerToken()

        let original = try service.loadOrCreateBearerToken()
        let rotated = try service.rotateBearerToken()

        #expect(rotated != original)
        #expect(try service.loadOrCreateBearerToken() == rotated)

        try service.deleteBearerToken()
    }
}

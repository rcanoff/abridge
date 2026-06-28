@testable import AppleBridge
import Foundation

/// In-memory `BearerTokenStoring` for unit tests. Avoids macOS Keychain access prompts.
final class MockBearerTokenStore: BearerTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToken: String?

    init(storedToken: String? = nil) {
        self.storedToken = storedToken
    }

    func loadOrCreateBearerToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let storedToken, !storedToken.isEmpty {
            return storedToken
        }
        let token = try Self.generateToken()
        storedToken = token
        return token
    }

    func rotateBearerToken() throws -> String {
        lock.lock()
        storedToken = nil
        lock.unlock()
        return try loadOrCreateBearerToken()
    }

    private static func generateToken() throws -> String {
        try APIKeyFormatting.generateAPIKey()
    }
}

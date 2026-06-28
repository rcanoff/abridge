import Foundation
import Security

enum APIKeyFormatting {
    static let livePrefix = "ab_live_"

    private static let randomByteCount = 32

    static func generateAPIKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: randomByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomByteCount, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError(message: "failed to generate random bytes (status \(status))")
        }
        return livePrefix + base64URLEncode(bytes)
    }

    static func isLegacyKey(_ key: String) -> Bool {
        !key.hasPrefix(livePrefix)
    }

    static func maskAPIKey(_ key: String) -> String {
        if key.hasPrefix(livePrefix) {
            let segment = String(key.dropFirst(livePrefix.count))
            return livePrefix + maskBody(segment)
        }
        return maskBody(key)
    }

    private static let visibleSuffixCount = 4
    private static let maskCharacter = "•"

    private static func maskBody(_ body: String) -> String {
        guard body.count > visibleSuffixCount else {
            return String(repeating: maskCharacter, count: body.count)
        }

        let hiddenCount = body.count - visibleSuffixCount
        let suffix = String(body.suffix(visibleSuffixCount))
        return String(repeating: maskCharacter, count: hiddenCount) + suffix
    }

    private static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
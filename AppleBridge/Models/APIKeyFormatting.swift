import Foundation
import Security

enum APIKeyFormatting {
    static let livePrefix = "ab_live_"

    private static let randomByteCount = 32

    static func generateAPIKey() -> String {
        var bytes = [UInt8](repeating: 0, count: randomByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomByteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (status \(status))")
        return livePrefix + base64URLEncode(bytes)
    }

    static func isLegacyKey(_ key: String) -> Bool {
        !key.hasPrefix(livePrefix)
    }

    private static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
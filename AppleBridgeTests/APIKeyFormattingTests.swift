@testable import AppleBridge
import Foundation
import Testing

@Suite("APIKeyFormatting")
struct APIKeyFormattingTests {
    private static let base64URLCharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    @Test
    func generateAPIKeyUsesLivePrefix() {
        let key = APIKeyFormatting.generateAPIKey()
        #expect(key.hasPrefix(APIKeyFormatting.livePrefix))
    }

    @Test
    func generateAPIKeyHas43CharUnpaddedBase64URLSegment() {
        let key = APIKeyFormatting.generateAPIKey()
        let segment = String(key.dropFirst(APIKeyFormatting.livePrefix.count))

        #expect(segment.count == 43)
        #expect(segment.unicodeScalars.allSatisfy { Self.base64URLCharacterSet.contains($0) })
        #expect(!segment.contains("+"))
        #expect(!segment.contains("/"))
        #expect(!segment.contains("="))
    }

    @Test
    func generateAPIKeyProducesDistinctValues() {
        let keys = (0 ..< 10).map { _ in APIKeyFormatting.generateAPIKey() }
        #expect(Set(keys).count == keys.count)
    }

    @Test
    func isLegacyKeyReturnsTrueWithoutLivePrefix() {
        #expect(APIKeyFormatting.isLegacyKey("existing-token"))
        #expect(APIKeyFormatting.isLegacyKey(""))
        #expect(APIKeyFormatting.isLegacyKey("a1b2c3d4e5f6789012345678901234ab"))
    }

    @Test
    func isLegacyKeyReturnsFalseWithLivePrefix() {
        let key = APIKeyFormatting.generateAPIKey()
        #expect(!APIKeyFormatting.isLegacyKey(key))
    }

    @Test
    func livePrefixConstant() {
        #expect(APIKeyFormatting.livePrefix == "ab_live_")
    }
}
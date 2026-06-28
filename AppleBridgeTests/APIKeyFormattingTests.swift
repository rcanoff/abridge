@testable import AppleBridge
import Foundation
import Testing

@Suite("APIKeyFormatting")
struct APIKeyFormattingTests {
    private static let base64URLCharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    @Test
    func generateAPIKeyUsesLivePrefix() throws {
        let key = try APIKeyFormatting.generateAPIKey()
        #expect(key.hasPrefix(APIKeyFormatting.livePrefix))
    }

    @Test
    func generateAPIKeyHas43CharUnpaddedBase64URLSegment() throws {
        let key = try APIKeyFormatting.generateAPIKey()
        let segment = String(key.dropFirst(APIKeyFormatting.livePrefix.count))

        #expect(segment.count == 43)
        #expect(segment.unicodeScalars.allSatisfy { Self.base64URLCharacterSet.contains($0) })
        #expect(!segment.contains("+"))
        #expect(!segment.contains("/"))
        #expect(!segment.contains("="))
    }

    @Test
    func generateAPIKeyProducesDistinctValues() throws {
        let keys = try (0 ..< 10).map { _ in try APIKeyFormatting.generateAPIKey() }
        #expect(Set(keys).count == keys.count)
    }

    @Test
    func isLegacyKeyReturnsTrueWithoutLivePrefix() {
        #expect(APIKeyFormatting.isLegacyKey("existing-token"))
        #expect(APIKeyFormatting.isLegacyKey(""))
        #expect(APIKeyFormatting.isLegacyKey("a1b2c3d4e5f6789012345678901234ab"))
    }

    @Test
    func isLegacyKeyReturnsFalseWithLivePrefix() throws {
        let key = try APIKeyFormatting.generateAPIKey()
        #expect(!APIKeyFormatting.isLegacyKey(key))
    }

    @Test
    func livePrefixConstant() {
        #expect(APIKeyFormatting.livePrefix == "ab_live_")
    }

    @Test
    func maskAPIKeyShowsPrefixAndMasksLiveKeySegment() {
        let segment = String(repeating: "A", count: 39) + "3f9a"
        let key = APIKeyFormatting.livePrefix + segment

        let masked = APIKeyFormatting.maskAPIKey(key)

        #expect(masked == APIKeyFormatting.livePrefix + String(repeating: "•", count: 39) + "3f9a")
        #expect(!masked.contains("AAAA"))
    }

    @Test
    func maskAPIKeyMasksLegacyHexKey() {
        let key = "a1b2c3d4e5f6789012345678901234ab"

        let masked = APIKeyFormatting.maskAPIKey(key)

        #expect(masked == String(repeating: "•", count: 28) + "34ab")
        #expect(!masked.contains("a1b2"))
    }

    @Test
    func maskAPIKeyFullyMasksShortKeys() {
        #expect(APIKeyFormatting.maskAPIKey("") == "")
        #expect(APIKeyFormatting.maskAPIKey("ab") == "••")
        #expect(APIKeyFormatting.maskAPIKey("1234") == "••••")
    }

    @Test
    func maskAPIKeyShowsLastFourForFiveCharacterLegacyKey() {
        #expect(APIKeyFormatting.maskAPIKey("12345") == "•2345")
    }

    @Test
    func maskAPIKeyFullyMasksShortLiveKeySegment() {
        let key = APIKeyFormatting.livePrefix + "abc"

        #expect(APIKeyFormatting.maskAPIKey(key) == APIKeyFormatting.livePrefix + "•••")
    }

    @Test
    func maskAPIKeyShowsPrefixWhenLiveKeySegmentIsEmpty() {
        #expect(APIKeyFormatting.maskAPIKey(APIKeyFormatting.livePrefix) == APIKeyFormatting.livePrefix)
    }
}
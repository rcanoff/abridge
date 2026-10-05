@testable import ABridge
import Foundation
import Testing

@Suite("SchemaTrustedPayload")
struct SchemaTrustedPayloadTests {
    @Test
    func requiredStringMissingOrWrongTypeIsEmpty() {
        #expect(SchemaTrustedPayload.requiredString([:], "title") == "")
        #expect(SchemaTrustedPayload.requiredString(["title": NSNull()], "title") == "")
        #expect(SchemaTrustedPayload.requiredString(["title": 1], "title") == "")
        #expect(SchemaTrustedPayload.requiredString(["title": "ok"], "title") == "ok")
    }

    @Test
    func requiredArrayMissingNullOrWrongTypeIsEmpty() {
        #expect(SchemaTrustedPayload.requiredArray([:], "alarms").isEmpty)
        #expect(SchemaTrustedPayload.requiredArray(["alarms": NSNull()], "alarms").isEmpty)
        #expect(SchemaTrustedPayload.requiredArray(["alarms": "nope"], "alarms").isEmpty)
        #expect(SchemaTrustedPayload.requiredArray(["alarms": 3], "alarms").isEmpty)
        let present = SchemaTrustedPayload.requiredArray(["alarms": [["relative_offset": 0]]], "alarms")
        #expect(present.count == 1)
    }

    @Test
    func requiredObjectMissingNullOrWrongTypeIsEmpty() {
        #expect(SchemaTrustedPayload.requiredObject([:], "source").isEmpty)
        #expect(SchemaTrustedPayload.requiredObject(["source": NSNull()], "source").isEmpty)
        #expect(SchemaTrustedPayload.requiredObject(["source": "nope"], "source").isEmpty)
        let present = SchemaTrustedPayload.requiredObject(
            ["source": ["coordinate": ["latitude": 1.0, "longitude": 2.0]]],
            "source"
        )
        #expect(present["coordinate"] != nil)
    }

    @Test
    func optionalArrayAndObjectHonorNullAndMissing() {
        #expect(SchemaTrustedPayload.optionalArray([:], "items") == nil)
        #expect(SchemaTrustedPayload.optionalArray(["items": NSNull()], "items") == nil)
        #expect(SchemaTrustedPayload.optionalArray(["items": "x"], "items") == nil)
        #expect(SchemaTrustedPayload.optionalArray(["items": [1, 2]], "items")?.count == 2)

        #expect(SchemaTrustedPayload.optionalObject([:], "region") == nil)
        #expect(SchemaTrustedPayload.optionalObject(["region": NSNull()], "region") == nil)
        #expect(SchemaTrustedPayload.optionalObject(["region": "x"], "region") == nil)
        #expect(SchemaTrustedPayload.optionalObject(["region": ["a": 1]], "region")?["a"] as? Int == 1)
    }
}

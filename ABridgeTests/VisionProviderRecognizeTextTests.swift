@testable import ABridge
import Darwin
import Foundation
import Testing
import Vision

@Suite("VisionProviderRecognizeText")
struct VisionProviderRecognizeTextTests {
    @Test
    @MainActor
    func recognizeTextRejectsInvalidBase64() {
        let provider = VisionProvider(store: MockVisionStore())
        let response = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"not-valid-base64!!!"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("base64") == true)
    }

    @Test
    @MainActor
    func recognizeTextReturnsSerializedResults() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let store = MockVisionStore()
        store.observations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        let response = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )

        #expect(response.ok == true)
        let payloadData = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        let results = decoded?["results"] as? [[String: Any]]
        #expect(results?.isEmpty == false)
        #expect(results?.first?.keys.contains("candidates") == true)
    }

    @Test
    @MainActor
    func recognizeTextForwardsMaxCandidateCountToSerialization() throws {
        let observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let store = MockVisionStore()
        store.observations = observations
        let provider = VisionProvider(store: store)
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let encoded = imageData.base64EncodedString()

        _ = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)","max_candidate_count":2}"#
        )

        #expect(store.lastRequest?.maxCandidateCount == 2)
    }

    @Test
    @MainActor
    func recognizeTextReadsAnAbsoluteImagePath() throws {
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).png")
        try imageData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MockVisionStore()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"\#(url.path)"}"#
        )
        #expect(response.ok == true)
        #expect(store.lastRequest?.imageData == imageData)
    }

    @Test
    @MainActor
    func recognizeTextRejectsBothImageSourcesAndARelativePath() {
        let provider = VisionProvider(store: MockVisionStore())
        let both = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"aGVsbG8=","image_path":"/tmp/receipt.png"}"#
        )
        #expect(both.ok == false)
        #expect(both.errorJson?.contains("exactly one of image_data or image_path") == true)

        let relative = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"receipt.png"}"#
        )
        #expect(relative.ok == false)
        #expect(relative.errorJson?.contains("absolute path") == true)

        let missing = provider.handle(operation: "recognize_text", payloadJson: "{}")
        #expect(missing.ok == false)
        #expect(missing.errorJson?.contains("exactly one of image_data or image_path") == true)
    }

    @Test
    @MainActor
    func recognizeTextRejectsAnImageLargerThanTheFileCap() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).bin")
        let oversized = VisionImageLimits.maxFileBytes + 1
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(oversized))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }

        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"\#(url.path)"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("20 MiB") == true)
    }

    @Test
    @MainActor
    func recognizeTextRejectsAFifoBeforeReading() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).fifo")
        #expect(mkfifo(url.path, 0o600) == 0)
        defer { try? FileManager.default.removeItem(at: url) }

        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"\#(url.path)"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("not a file") == true)
    }

    @Test
    @MainActor
    func recognizeTextFollowsASymlinkToARegularFile() throws {
        let imageData = try VisionTestFixtures.sampleTextImageData()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).png")
        try imageData.write(to: file)
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: file)
        }

        let store = MockVisionStore()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"\#(link.path)"}"#
        )
        #expect(response.ok == true)
        #expect(store.lastRequest?.imageData == imageData)
    }
}

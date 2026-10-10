@testable import ABridge
import Foundation
import Testing
import Vision

/// Live Vision on a screenshot whose status lines Vision reports as lists nested inside their own
/// items without end. Serializing that chain used to recurse until the stack overflowed.
@Suite("VisionRecognizeDocumentsSelfNesting")
struct VisionRecognizeDocumentsSelfNestingTests {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/vision-self-nesting-lists.png")

    /// Whether this machine's Vision reports the fixture's lists inside their own items. Asked of
    /// Vision directly, two levels deep; virtual machines without that model behavior skip the test.
    private static let visionNestsFixtureLists: Bool = {
        guard let imageData = try? Data(contentsOf: fixtureURL) else { return false }
        return (try? VisionAsyncBridge.perform(operation: "Vision fixture probe", timeout: 60) {
            let observations = try await ImageRequestHandler(imageData).perform(RecognizeDocumentsRequest())
            let item = observations.first?.document.lists.first?.items.first
            return item?.content.lists.isEmpty == false
        }) ?? false
    }()

    @Test(
        .enabled(if: visionNestsFixtureLists, "Vision on this machine does not nest the fixture's lists"),
        .timeLimit(.minutes(2))
    )
    func recognizeDocumentsWritesSelfNestingListsOnce() throws {
        let imageData = try Data(contentsOf: Self.fixtureURL)
        let arguments = ["image_data": imageData.base64EncodedString()]
        let payload = try #require(String(data: JSONSerialization.data(withJSONObject: arguments), encoding: .utf8))

        let response = VisionProvider().handle(operation: "recognize_documents", payloadJson: payload)

        #expect(response.ok, "\(response.errorJson ?? "")")
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(response.payloadJson.utf8)) as? [String: Any]
        )
        let results = try #require(json["results"] as? [[String: Any]])
        let document = try #require(results.first?["document"] as? [String: Any])
        let maxListDepth = Self.maximumListDepth(in: document)
        #expect(maxListDepth >= 1)
        #expect(maxListDepth <= 3)
    }

    /// Deepest chain of `lists` → `items` → `content` below a container.
    private static func maximumListDepth(in container: [String: Any]) -> Int {
        let lists = container["lists"] as? [[String: Any]] ?? []
        return lists.map { list in
            let items = list["items"] as? [[String: Any]] ?? []
            let deepest = items.map { item in
                (item["content"] as? [String: Any]).map(maximumListDepth(in:)) ?? 0
            }.max() ?? 0
            return 1 + deepest
        }.max() ?? 0
    }
}

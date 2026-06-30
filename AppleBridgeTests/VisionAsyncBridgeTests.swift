@testable import AppleBridge
import Foundation
import Testing

@Suite("VisionAsyncBridge")
struct VisionAsyncBridgeTests {
    @Test
    func performReturnsResultWhenWorkCompletes() throws {
        let value = try VisionAsyncBridge.perform(operation: "Vision test", timeout: 1) {
            42
        }
        #expect(value == 42)
    }

    @Test
    func performTimesOutAndCancelsInFlightWork() async throws {
        let timeout: TimeInterval = 0.1
        let workContinued = WorkContinuationBox()

        do {
            _ = try VisionAsyncBridge.perform(operation: "Vision test", timeout: timeout) {
                try await Task.sleep(for: .seconds(1))
                workContinued.markContinued()
                return 42
            }
            Issue.record("Expected timeout")
        } catch let error as VisionProviderError {
            guard case let .visionError(message) = error else {
                Issue.record("Expected vision_error, got \(error)")
                return
            }
            #expect(message.contains("timed out"))
        }

        try await Task.sleep(for: .milliseconds(200))
        #expect(workContinued.didContinue() == false)
    }
}

private final class WorkContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continued = false

    func markContinued() {
        lock.lock()
        defer { lock.unlock() }
        continued = true
    }

    func didContinue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return continued
    }
}

import Foundation

enum VisionAsyncBridge {
    static let defaultTimeout: TimeInterval = 30
    static let runLoopModes: [RunLoop.Mode] = [.default, .eventTracking]
    static let runLoopInterval: TimeInterval = 0.01

    final class AsyncBridgeResult<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        private var error: Error?

        func setValue(_ value: T) {
            lock.lock()
            defer { lock.unlock() }
            self.value = value
        }

        func setError(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            self.error = error
        }

        func get() throws -> T {
            lock.lock()
            defer { lock.unlock() }
            if let error {
                throw error
            }
            guard let value else {
                throw VisionProviderError.visionError("Vision async bridge returned no value")
            }
            return value
        }
    }

    static func waitForCompletion(
        operation: String,
        timeout: TimeInterval = defaultTimeout,
        work: (@escaping () -> Void) -> Void
    ) throws {
        var done = false
        work {
            done = true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            pumpRunLoop(for: runLoopInterval)
        }

        guard done else {
            throw VisionProviderError.visionError("\(operation) timed out")
        }
    }

    static func pumpRunLoop(for interval: TimeInterval) {
        let perModeInterval = interval / Double(runLoopModes.count)
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: perModeInterval))
        }
    }
}

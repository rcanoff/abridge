import Foundation

/// Sync bridge for Vision under the UniFFI sync FFI.
///
/// **Critical:** Vision work never runs on the main thread. A request can take seconds, and on the
/// main thread it froze the menu bar for that long. Work runs on one dedicated worker thread, which
/// keeps long synchronous Vision calls off the cooperative pool too; the caller waits until it
/// finishes or times out.
enum VisionAsyncBridge {
    static let defaultTimeout: TimeInterval = 30

    /// Same as the main thread's stack, where Vision work used to run.
    static let workerStackSize = 8 * 1024 * 1024

    private static let worker = VisionWorkerExecutor(stackSize: workerStackSize)

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

    /// Runs `work` on the Vision worker thread and blocks the calling thread until it finishes.
    /// On timeout the work is cancelled and `vision_error` reports which operation timed out.
    /// Call it once per operation, never from Vision work itself: the single worker would wait on itself.
    static func perform<T>(
        operation: String,
        timeout: TimeInterval = defaultTimeout,
        work: @Sendable @escaping () async throws -> T
    ) throws -> T {
        let result = AsyncBridgeResult<T>()
        let finished = DispatchSemaphore(value: 0)

        let task = Task(executorPreference: worker) {
            defer { finished.signal() }
            do {
                try Task.checkCancellation()
                let value = try await work()
                try Task.checkCancellation()
                result.setValue(value)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                result.setError(error)
            }
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw VisionProviderError.visionError("\(operation) timed out")
        }

        return try result.get()
    }
}

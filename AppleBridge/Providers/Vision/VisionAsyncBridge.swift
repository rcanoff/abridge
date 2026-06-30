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

    private final class CompletionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var cancelled = false
        private var task: Task<Void, Never>?

        func setTask(_ task: Task<Void, Never>) {
            lock.lock()
            defer { lock.unlock() }
            self.task = task
            if cancelled {
                task.cancel()
            }
        }

        func markDone() {
            lock.lock()
            defer { lock.unlock() }
            done = true
        }

        func isDone() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return done
        }

        func cancelTask() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            task?.cancel()
        }
    }

    static func perform<T>(
        operation: String,
        timeout: TimeInterval = defaultTimeout,
        work: @Sendable @escaping () async throws -> T
    ) throws -> T {
        let result = AsyncBridgeResult<T>()
        let completion = CompletionBox()

        DispatchQueue.main.async {
            let asyncTask = Task {
                defer { completion.markDone() }
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
            completion.setTask(asyncTask)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !completion.isDone(), Date() < deadline {
            pumpRunLoop(for: runLoopInterval)
        }

        if !completion.isDone() {
            completion.cancelTask()
            throw VisionProviderError.visionError("\(operation) timed out")
        }

        return try result.get()
    }

    static func pumpRunLoop(for interval: TimeInterval) {
        let perModeInterval = interval / Double(runLoopModes.count)
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: perModeInterval))
        }
    }
}

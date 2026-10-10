import Foundation

protocol MainQueueCallbackWaitFailure: Error {
    static func callbackWaitFailed(_ message: String) -> Self
}

/// Starts work on the main queue, then waits off-main until a completion callback fires.
///
/// **Critical:** MapKit completions and Core Location delegate callbacks do not fire while a
/// main-queue item is blocked (including `DispatchQueue.main.sync` + `RunLoop` pumping).
/// Start work on the main queue, then wait on a **background** thread so the main run loop
/// stays free.
enum MainQueueCallbackWait<Failure: MainQueueCallbackWaitFailure> {
    /// Upper bound while waiting for a main-queue callback to finish.
    static var defaultTimeout: TimeInterval {
        30
    }

    /// Modes pumped for main-thread waiters (unit tests / rare main callers).
    static var runLoopModes: [RunLoop.Mode] {
        [.default, .common, .eventTracking]
    }

    static var runLoopInterval: TimeInterval {
        0.01
    }

    /// Thread-safe handoff for sync/async main-queue callbacks.
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
                throw Failure.callbackWaitFailed("Async bridge returned no result")
            }
            return value
        }
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func fire(_ semaphore: DispatchSemaphore) {
            lock.lock()
            defer { lock.unlock() }
            guard !fired else { return }
            fired = true
            semaphore.signal()
        }

        var hasFired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }
    }

    /// Starts `work` on the main queue (it must schedule the callback source and return quickly),
    /// then waits until `complete` is called.
    ///
    /// - Off main (production FFI): `DispatchQueue.main.async` + semaphore wait on this thread.
    /// - On main (tests): enqueue `work`, then pump the run loop until done or timeout.
    static func waitForCompletion(
        operation: String,
        timeout: TimeInterval = defaultTimeout,
        work: @escaping (@escaping @Sendable () -> Void) -> Void
    ) throws {
        // Request types are non-Sendable; this bridge is single-flight per call.
        nonisolated(unsafe) let startWork = work

        if Thread.isMainThread {
            // Unit tests only (production FFI is always off-main). Start work inline
            // and pump so Timer / test seams fire. Prefer run-loop sources over
            // bare `Task` in main-thread tests — Task may not progress under this pump.
            let semaphore = DispatchSemaphore(value: 0)
            let once = OnceFlag()
            let complete: @Sendable () -> Void = { once.fire(semaphore) }
            startWork(complete)
            let deadline = Date().addingTimeInterval(timeout)
            while !once.hasFired, Date() < deadline {
                pumpRunLoop(for: runLoopInterval)
            }
            guard once.hasFired else {
                throw Failure.callbackWaitFailed("\(operation) timed out")
            }
            return
        }

        try waitOffMain(operation: operation, timeout: timeout, startWork: startWork)
    }

    /// Start work on the main queue; wait on the calling (background) thread.
    private static func waitOffMain(
        operation: String,
        timeout: TimeInterval,
        startWork: @escaping (@escaping @Sendable () -> Void) -> Void
    ) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let once = OnceFlag()
        let complete: @Sendable () -> Void = { once.fire(semaphore) }
        nonisolated(unsafe) let startWork = startWork

        DispatchQueue.main.async {
            startWork(complete)
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        guard waitResult == .success else {
            throw Failure.callbackWaitFailed("\(operation) timed out")
        }
    }

    static func pumpRunLoop(for interval: TimeInterval) {
        let perModeInterval = interval / Double(runLoopModes.count)
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: perModeInterval))
        }
    }
}

import Foundation

@MainActor
enum EventKitReminderFetch {
    /// Upper bound for blocking the main actor while EventKit delivers its callback.
    /// Kept short so stalled fetches cannot freeze menu bar UI for extended periods.
    static let defaultTimeout: TimeInterval = 5

    /// Modes pumped while waiting so EventKit callbacks and user-input sources stay serviced.
    static let runLoopModes: [RunLoop.Mode] = [.default, .eventTracking]

    static let runLoopInterval: TimeInterval = 0.01

    static func waitForCompletion(
        timeout: TimeInterval = defaultTimeout,
        work: (@escaping () -> Void) -> Void
    ) throws {
        var done = false
        work {
            done = true
        }

        // EventKit delivers the completion on the main run loop. Spin explicitly on `.main`
        // (not `.current`) so this stays correct when called via `DispatchQueue.main.sync`.
        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            pumpRunLoop(until: Date(timeIntervalSinceNow: runLoopInterval))
        }

        guard done else {
            throw EventKitProviderError.reminderFetchTimedOut
        }
    }

    /// Pump common run loop modes so EventKit completions and UI events can fire during sync FFI waits.
    static func pumpRunLoop(until date: Date) {
        for mode in runLoopModes {
            RunLoop.main.run(mode: mode, before: date)
        }
    }
}

import AppKit
import Foundation

struct RunningApplicationInstanceChecker: SingleInstanceChecking {
    private let bundleIdentifier: @Sendable () -> String?
    private let runningApplicationCount: @Sendable (String) -> Int

    init(
        bundleIdentifier: @escaping @Sendable () -> String? = { Bundle.main.bundleIdentifier },
        runningApplicationCount: @escaping @Sendable (String) -> Int = { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.runningApplicationCount = runningApplicationCount
    }

    func isDuplicateLaunch() -> Bool {
        guard let bundleID = bundleIdentifier() else { return false }
        return runningApplicationCount(bundleID) > 1
    }
}

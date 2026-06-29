import AppKit
import Foundation

struct RunningApplicationInstanceChecker: SingleInstanceChecking {
    private let bundleIdentifier: @Sendable () -> String?
    private let currentProcessIdentifier: @Sendable () -> pid_t
    private let hasOtherRunningInstance: @Sendable (String, pid_t) -> Bool

    init(
        bundleIdentifier: @escaping @Sendable () -> String? = { Bundle.main.bundleIdentifier },
        currentProcessIdentifier: @escaping @Sendable () -> pid_t = { ProcessInfo.processInfo.processIdentifier },
        hasOtherRunningInstance: @escaping @Sendable (String, pid_t) -> Bool = Self.detectOtherRunningInstance
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentProcessIdentifier = currentProcessIdentifier
        self.hasOtherRunningInstance = hasOtherRunningInstance
    }

    func isDuplicateLaunch() -> Bool {
        guard let bundleID = bundleIdentifier() else { return false }
        return hasOtherRunningInstance(bundleID, currentProcessIdentifier())
    }

    /// Production duplicate detection via `NSRunningApplication`.
    static func detectOtherRunningInstance(bundleID: String, currentPID: pid_t) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["APPLE_BRIDGE_TEST_DUPLICATE_LAUNCH"] == "1" {
            return true
        }
        #endif
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != currentPID }
    }
}

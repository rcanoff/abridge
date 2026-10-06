@testable import ABridge
import AppKit

@MainActor
final class MockActivationPolicyApplier: AppActivationPolicyApplying {
    private(set) var appliedPolicies: [NSApplication.ActivationPolicy] = []

    func apply(_ policy: NSApplication.ActivationPolicy) {
        appliedPolicies.append(policy)
    }
}

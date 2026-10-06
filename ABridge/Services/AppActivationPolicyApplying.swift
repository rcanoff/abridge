import AppKit

@MainActor
protocol AppActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy)
}

@MainActor
struct NSApplicationActivationPolicyApplier: AppActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}

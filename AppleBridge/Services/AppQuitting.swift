import AppKit
import Foundation

@MainActor
protocol AppQuitting {
    func terminate()
}

@MainActor
struct NSApplicationQuitter: AppQuitting {
    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}

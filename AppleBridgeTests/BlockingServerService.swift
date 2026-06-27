import Foundation
@testable import AppleBridge

@MainActor
final class BlockingServerService: ServerServing {
    private(set) var startCallCount = 0
    private var isBlocked = false

    func refreshStatus() -> ServerRunState {
        .stopped
    }

    func start(host: String, port: UInt16) throws {
        startCallCount += 1
        isBlocked = true
        while isBlocked {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    func stop() throws {}

    func resume() {
        isBlocked = false
    }
}
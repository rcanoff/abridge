import Foundation
@testable import AppleBridge

@MainActor
final class MockServerService: ServerServing {
    var refreshResult: ServerRunState = .stopped
    var startError: ServerOperationError?
    var stopError: ServerOperationError?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartHost: String?
    private(set) var lastStartPort: UInt16?

    func refreshStatus() -> ServerRunState {
        refreshResult
    }

    func start(host: String, port: UInt16) throws {
        startCallCount += 1
        lastStartHost = host
        lastStartPort = port

        if let startError {
            throw startError
        }
    }

    func stop() throws {
        stopCallCount += 1
        refreshResult = .stopped

        if let stopError {
            throw stopError
        }
    }
}
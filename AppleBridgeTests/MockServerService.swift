import Foundation
@testable import AppleBridge

actor MockServerService: ServerServing {
    var refreshResult: ServerRunState = .stopped
    var startError: ServerOperationError?
    var stopError: ServerOperationError?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartHost: String?
    private(set) var lastStartPort: UInt16?

    func refreshStatus() async -> ServerRunState {
        refreshResult
    }

    func start(host: String, port: UInt16) async throws {
        startCallCount += 1
        lastStartHost = host
        lastStartPort = port

        if let startError {
            throw startError
        }
    }

    func stop() async throws {
        stopCallCount += 1
        refreshResult = .stopped

        if let stopError {
            throw stopError
        }
    }

    func setRefreshResult(_ result: ServerRunState) {
        refreshResult = result
    }

    func setStartError(_ error: ServerOperationError?) {
        startError = error
    }
}
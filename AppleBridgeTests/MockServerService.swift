@testable import AppleBridge
import Foundation

actor MockServerService: ServerServing {
    var refreshResult: ServerRunState = .stopped
    var bearerTokenResult = "mock-bearer-token"
    var loadBearerTokenError: ServerOperationError?
    var startError: ServerOperationError?
    var stopError: ServerOperationError?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartHost: String?
    private(set) var lastStartPort: UInt16?
    private(set) var activeBearerToken: String?

    func refreshStatus() async -> ServerRunState {
        refreshResult
    }

    func loadBearerToken() async throws -> String {
        if let loadBearerTokenError {
            throw loadBearerTokenError
        }
        return bearerTokenResult
    }

    func activeBearerToken() async -> String? {
        activeBearerToken
    }

    func start(host: String, port: UInt16) async throws {
        startCallCount += 1
        lastStartHost = host
        lastStartPort = port

        if let startError {
            throw startError
        }

        activeBearerToken = bearerTokenResult
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

    func setBearerTokenResult(_ token: String) {
        bearerTokenResult = token
    }
}

@testable import AppleBridge
import Foundation

actor MockServerService: ServerServing {
    var refreshResult: ServerRunState = .stopped
    var bearerTokenResult = "mock-bearer-token"
    var loadBearerTokenError: ServerOperationError?
    var startError: ServerOperationError?
    var stopError: ServerOperationError?
    var resetBearerTokenError: ServerOperationError?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartHost: String?
    private(set) var lastStartPort: UInt16?
    private(set) var lastEnabledCapabilities: [String]?
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

    func start(host: String, port: UInt16, enabledCapabilities: [String]) async throws {
        startCallCount += 1
        lastStartHost = host
        lastStartPort = port
        lastEnabledCapabilities = enabledCapabilities

        if let startError {
            throw startError
        }

        activeBearerToken = bearerTokenResult
        refreshResult = .running
    }

    func stop() async throws {
        stopCallCount += 1
        refreshResult = .stopped

        if let stopError {
            throw stopError
        }
    }

    func resetBearerToken() async throws -> String {
        if let resetBearerTokenError {
            throw resetBearerTokenError
        }

        bearerTokenResult = "rotated-\(bearerTokenResult)"
        activeBearerToken = bearerTokenResult
        refreshResult = .stopped
        return bearerTokenResult
    }

    func setRefreshResult(_ result: ServerRunState) {
        refreshResult = result
    }

    func setStartError(_ error: ServerOperationError?) {
        startError = error
    }

    func setResetBearerTokenError(_ error: ServerOperationError?) {
        resetBearerTokenError = error
    }

    func setBearerTokenResult(_ token: String) {
        bearerTokenResult = token
    }
}

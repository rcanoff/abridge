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
    private(set) var lastStartUsageLoggingEnabled: Bool?
    private(set) var activeBearerToken: String?
    private(set) var usageLoggingEnabledState = true
    private(set) var setUsageLoggingEnabledCallCount = 0
    private(set) var recordApiKeyRotationCallCount = 0
    private(set) var usageAuditEntriesResult: [UsageAuditEntry] = []

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

    func start(
        host: String,
        port: UInt16,
        enabledCapabilities: [String],
        usageLoggingEnabled: Bool
    ) async throws {
        startCallCount += 1
        lastStartHost = host
        lastStartPort = port
        lastEnabledCapabilities = enabledCapabilities
        lastStartUsageLoggingEnabled = usageLoggingEnabled

        if let startError {
            throw startError
        }

        usageLoggingEnabledState = usageLoggingEnabled
        activeBearerToken = bearerTokenResult
        refreshResult = .running
    }

    func stop() async throws {
        stopCallCount += 1
        refreshResult = .stopped
        activeBearerToken = nil

        if let stopError {
            throw stopError
        }
    }

    func resetBearerToken() async throws -> String {
        if let resetBearerTokenError {
            throw resetBearerTokenError
        }

        if refreshResult == .running {
            recordApiKeyRotationCallCount += 1
            try await stop()
        }
        bearerTokenResult = "rotated-\(bearerTokenResult)"
        activeBearerToken = bearerTokenResult
        return bearerTokenResult
    }

    func setUsageLoggingEnabled(_ enabled: Bool) async {
        setUsageLoggingEnabledCallCount += 1
        usageLoggingEnabledState = enabled
    }

    func usageLoggingEnabled() async -> Bool {
        usageLoggingEnabledState
    }

    func usageAuditEntries() async -> [UsageAuditEntry] {
        usageAuditEntriesResult
    }

    func replaceTokenStore(_: any BearerTokenStoring) async {}

    func setUsageAuditEntriesResult(_ entries: [UsageAuditEntry]) {
        usageAuditEntriesResult = entries
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

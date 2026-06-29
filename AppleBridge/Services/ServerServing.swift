import Foundation

protocol ServerServing: Sendable {
    func refreshStatus() async -> ServerRunState
    func loadBearerToken() async throws -> String
    func activeBearerToken() async -> String?
    func start(
        host: String,
        port: UInt16,
        enabledCapabilities: [String],
        usageLoggingEnabled: Bool
    ) async throws
    func stop() async throws
    func resetBearerToken() async throws -> String
    func setUsageLoggingEnabled(_ enabled: Bool) async
    func usageLoggingEnabled() async -> Bool
    func usageAuditEntries() async -> [UsageAuditEntry]
    func replaceTokenStore(_ store: any BearerTokenStoring) async
}

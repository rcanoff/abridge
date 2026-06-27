import Foundation

protocol ServerServing: Sendable {
    func refreshStatus() async -> ServerRunState
    func loadBearerToken() async throws -> String
    func activeBearerToken() async -> String?
    func start(host: String, port: UInt16) async throws
    func stop() async throws
}

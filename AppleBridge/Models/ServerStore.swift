import Foundation
import Observation

@Observable
@MainActor
final class ServerStore {
    private(set) var runState: ServerRunState = .stopped
    private(set) var isStarting = false
    private(set) var lastError: String?
    private(set) var bearerToken: String?

    let host = "127.0.0.1"
    let port: UInt16 = 3020

    private let serverService: any ServerServing

    init(serverService: any ServerServing = ServerService()) {
        self.serverService = serverService
    }

    func refreshStatus() async {
        let state = await serverService.refreshStatus()
        runState = state

        if case let .error(message) = state {
            lastError = message
        } else {
            lastError = nil
        }
    }

    func refreshBearerToken() async {
        if runState == .running, let activeToken = await serverService.activeBearerToken() {
            bearerToken = activeToken
            return
        }

        do {
            bearerToken = try await serverService.loadBearerToken()
        } catch let error as ServerOperationError {
            lastError = error.message
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startServer() async {
        guard !isStarting, runState != .running, runState != .starting else { return }

        isStarting = true
        lastError = nil
        runState = .starting

        defer { isStarting = false }

        do {
            try await serverService.start(host: host, port: port)
            await refreshBearerToken()
            let state = await serverService.refreshStatus()
            runState = state
            if case let .error(message) = state {
                lastError = message
            } else {
                lastError = nil
            }
        } catch let error as ServerOperationError {
            lastError = error.message
            runState = .error(error.message)
        } catch {
            lastError = error.localizedDescription
            runState = .error(error.localizedDescription)
        }
    }

    func stopServer() async {
        do {
            try await serverService.stop()
            await refreshStatus()
        } catch let error as ServerOperationError {
            lastError = error.message
            runState = .error(error.message)
        } catch {
            lastError = error.localizedDescription
            runState = .error(error.localizedDescription)
        }
    }
}

import Foundation
import Observation

@Observable
@MainActor
final class ServerStore {
    private(set) var runState: ServerRunState = .stopped
    private(set) var isStarting = false
    private(set) var lastError: String?

    let host = "127.0.0.1"
    let port: UInt16 = 3020

    private let serverService: any ServerServing

    init(serverService: any ServerServing = ServerService()) {
        self.serverService = serverService
    }

    func refreshStatus() {
        runState = serverService.refreshStatus()

        if case .error(let message) = runState {
            lastError = message
        } else {
            lastError = nil
        }
    }

    func startServer() {
        guard !isStarting, runState != .running, runState != .starting else { return }

        isStarting = true
        lastError = nil
        runState = .starting

        defer { isStarting = false }

        do {
            try serverService.start(host: host, port: port)
            runState = serverService.refreshStatus()
            if case .error(let message) = runState {
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

    func stopServer() {
        do {
            try serverService.stop()
            refreshStatus()
        } catch let error as ServerOperationError {
            lastError = error.message
            runState = .error(error.message)
        } catch {
            lastError = error.localizedDescription
            runState = .error(error.localizedDescription)
        }
    }
}
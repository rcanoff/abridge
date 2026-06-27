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

    private let serverService: any ServerServing

    init(serverService: any ServerServing = ServerService()) {
        self.serverService = serverService
    }

    func refreshStatus() async {
        let state = await serverService.refreshStatus()

        // After a failed start there is no server handle, so the service reports
        // `.stopped`. Do not overwrite a recent startup error from launch restore
        // or manual start attempts.
        if case .stopped = state, case .error = runState, lastError != nil {
            return
        }

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

    func startServer(port: UInt16, enabledCapabilities: [String]) async {
        guard !isStarting, runState != .running, runState != .starting else { return }

        isStarting = true
        lastError = nil
        runState = .starting

        defer { isStarting = false }

        do {
            try await serverService.start(
                host: host,
                port: port,
                enabledCapabilities: enabledCapabilities
            )
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
            runState = .stopped
            lastError = nil
        } catch let error as ServerOperationError {
            lastError = error.message
            runState = .error(error.message)
        } catch {
            lastError = error.localizedDescription
            runState = .error(error.localizedDescription)
        }
    }

    func restartServer(port: UInt16, enabledCapabilities: [String]) async {
        await stopServer()
        await startServer(port: port, enabledCapabilities: enabledCapabilities)
    }

    func resetBearerToken(port: UInt16, enabledCapabilities: [String], restartIfRunning: Bool) async {
        let shouldRestart = restartIfRunning && runState == .running

        do {
            bearerToken = try await serverService.resetBearerToken()
            lastError = nil

            if shouldRestart {
                runState = .stopped
                await startServer(port: port, enabledCapabilities: enabledCapabilities)
            } else {
                await refreshStatus()
            }
        } catch let error as ServerOperationError {
            lastError = error.message
            runState = .error(error.message)
        } catch {
            lastError = error.localizedDescription
            runState = .error(error.localizedDescription)
        }
    }
}

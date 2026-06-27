import Foundation

struct ServerOperationError: Error, Equatable, Sendable {
    let message: String
}

actor ServerService: ServerServing {
    private var handle: ServerHandle?
    private var currentHost: String?
    private var currentPort: UInt16?
    private var hasInitializedLogging = false

    private let providerBridge: AppleProviderBridge

    init(providerBridge: AppleProviderBridge = AppleProviderBridge()) {
        self.providerBridge = providerBridge
    }

    func refreshStatus() async -> ServerRunState {
        guard let handle else {
            return .stopped
        }

        let status = serverStatus(handle: handle)

        if let error = status.lastError, !error.isEmpty {
            return .error(error)
        }

        return status.running ? .running : .stopped
    }

    func start(host: String, port: UInt16) async throws {
        if !hasInitializedLogging {
            initLogging()
            hasInitializedLogging = true
        }

        if handle != nil, currentHost != host || currentPort != port {
            try await stop()
        }

        if handle == nil {
            let config = ServerConfig(
                host: host,
                port: port,
                enabledProviders: [ProviderConfig(name: "eventkit", enabled: true)]
            )
            handle = try createServer(config: config, provider: providerBridge)
            currentHost = host
            currentPort = port
        }

        guard let handle else {
            throw ServerOperationError(message: ServerService.userMessage(for: .StateUnavailable))
        }

        do {
            try startServer(handle: handle)
        } catch let error as CoreError {
            throw ServerOperationError(message: ServerService.userMessage(for: error))
        }
    }

    func stop() async throws {
        guard let handle else { return }

        do {
            try stopServer(handle: handle)
        } catch let error as CoreError {
            throw ServerOperationError(message: ServerService.userMessage(for: error))
        }

        self.handle = nil
        currentHost = nil
        currentPort = nil
    }
}

extension ServerService {
    static func userMessage(for error: CoreError) -> String {
        switch error {
        case .InvalidConfig(let message):
            return "Invalid server configuration: \(message)"
        case .AlreadyRunning:
            return "Server is already running."
        case .StateUnavailable:
            return "Server state is unavailable."
        case .BindFailed(let message):
            return "Failed to bind server: \(message)"
        case .RuntimeFailed(let message):
            return "Server error: \(message)"
        case .StartCancelled:
            return "Server start was cancelled."
        }
    }
}
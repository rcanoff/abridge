import Foundation

struct ServerOperationError: Error, Equatable, Sendable {
    let message: String
}

actor ServerService: ServerServing {
    private var handle: ServerHandle?
    private var currentHost: String?
    private var currentPort: UInt16?
    private var currentBearerToken: String?
    private var hasInitializedLogging = false

    private let providerBridge: AppleProviderBridge
    private let tokenStore: any BearerTokenStoring

    init(
        providerBridge: AppleProviderBridge = AppleProviderBridge(),
        tokenStore: any BearerTokenStoring = KeychainService()
    ) {
        self.providerBridge = providerBridge
        self.tokenStore = tokenStore
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

    func loadBearerToken() async throws -> String {
        do {
            return try tokenStore.loadOrCreateBearerToken()
        } catch let error as KeychainError {
            throw ServerOperationError(message: "Failed to load bearer token: \(error.message)")
        }
    }

    func activeBearerToken() async -> String? {
        currentBearerToken
    }

    func start(host: String, port: UInt16) async throws {
        if !hasInitializedLogging {
            initLogging()
            hasInitializedLogging = true
        }

        let token = try await loadBearerToken()

        if handle != nil,
           currentHost != host || currentPort != port || currentBearerToken != token
        {
            try await stop()
        }

        if handle == nil {
            let config = ServerConfig(
                host: host,
                port: port,
                bearerToken: token,
                enabledProviders: [ProviderConfig(name: "eventkit", enabled: true)]
            )
            handle = try createServer(config: config, provider: providerBridge)
            currentHost = host
            currentPort = port
            currentBearerToken = token
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
        currentBearerToken = nil
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
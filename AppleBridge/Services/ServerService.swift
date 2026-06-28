import Foundation

struct ServerOperationError: Error, Equatable {
    let message: String
}

actor ServerService: ServerServing {
    private var handle: ServerHandle?
    private var currentHost: String?
    private var currentPort: UInt16?
    private var currentBearerToken: String?
    private var currentCapabilities: [String]?
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

    func start(
        host: String,
        port: UInt16,
        enabledCapabilities: [String],
        usageLoggingEnabled: Bool
    ) async throws {
        if !hasInitializedLogging {
            initLogging()
            hasInitializedLogging = true
        }

        let token = try await loadBearerToken()

        if handle != nil,
           currentHost != host || currentPort != port || currentBearerToken != token
           || currentCapabilities != enabledCapabilities
        {
            try await stop()
        }

        if handle == nil {
            let config = ServerConfig(
                host: host,
                port: port,
                bearerToken: token,
                enabledProviders: [
                    ProviderConfig(name: "eventkit", enabled: true),
                    ProviderConfig(name: "diagnostics", enabled: true),
                ],
                enabledCapabilities: enabledCapabilities
            )
            handle = try createServer(config: config, provider: providerBridge)
            currentHost = host
            currentPort = port
            currentBearerToken = token
            currentCapabilities = enabledCapabilities
        }

        guard let handle else {
            throw ServerOperationError(message: ServerService.userMessage(for: .StateUnavailable))
        }

        handle.setUsageLoggingEnabled(enabled: usageLoggingEnabled)

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
        currentCapabilities = nil
    }

    func resetBearerToken() async throws -> String {
        if let handle {
            handle.recordApiKeyRotation()
            try await stop()
        }

        do {
            let token = try tokenStore.rotateBearerToken()
            currentBearerToken = token
            return token
        } catch let error as KeychainError {
            throw ServerOperationError(message: "Failed to reset bearer token: \(error.message)")
        }
    }

    func setUsageLoggingEnabled(_ enabled: Bool) async {
        handle?.setUsageLoggingEnabled(enabled: enabled)
    }

    func usageLoggingEnabled() async -> Bool {
        guard let handle else { return true }
        return handle.usageLoggingEnabled()
    }

    func usageAuditEntries() async -> [UsageAuditEntry] {
        guard let handle else { return [] }
        return handle.usageAuditEntries()
    }
}

extension ServerService {
    static func userMessage(for error: CoreError) -> String {
        switch error {
        case let .InvalidConfig(message):
            "Invalid server configuration: \(message)"
        case .AlreadyRunning:
            "Server is already running."
        case .StateUnavailable:
            "Server state is unavailable."
        case let .BindFailed(message):
            "Failed to bind server: \(message)"
        case let .RuntimeFailed(message):
            "Server error: \(message)"
        case .StartCancelled:
            "Server start was cancelled."
        }
    }
}

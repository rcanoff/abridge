import Foundation
import Observation

enum SettingsTab: String, CaseIterable, Identifiable {
    case mcp
    case permissions
    case diagnostics
    case developer

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .mcp:
            "MCP"
        case .permissions:
            "Permissions"
        case .diagnostics:
            "Diagnostics"
        case .developer:
            "Developer"
        }
    }
}

@Observable
@MainActor
final class SettingsStore {
    var selectedTab: SettingsTab = .mcp
    private(set) var tokenResetNotice: String?
    private(set) var launchAtLoginError: String?
    private(set) var usageAuditEntries: [UsageAuditEntry] = []

    let appSettings: AppSettings

    private let serverStore: ServerStore
    private let permissionService: any RemindersPermissionChecking
    private let eventsPermissionService: any EventsPermissionChecking
    private let contactsPermissionService: any ContactsPermissionChecking
    private let locationPermissionService: any LocationPermissionChecking
    private let launchAtLoginService: any LaunchAtLoginManaging
    private let migrateTokenStorage: @Sendable (Bool, Bool) throws -> Void
    private var didPerformLaunchRestore = false
    private var didPerformLaunchAtLoginReconcile = false

    init(
        appSettings: AppSettings,
        serverStore: ServerStore,
        permissionService: any RemindersPermissionChecking = RemindersPermissionService(),
        eventsPermissionService: any EventsPermissionChecking = EventsPermissionService(),
        contactsPermissionService: any ContactsPermissionChecking = ContactsPermissionService(),
        locationPermissionService: any LocationPermissionChecking = LocationPermissionService(),
        launchAtLoginService: any LaunchAtLoginManaging = SMAppLaunchAtLoginService(),
        migrateTokenStorage: @escaping @Sendable (Bool, Bool) throws -> Void = { useKeychain, fromKeychainEnabled in
            try BearerTokenMigrator.migrate(useKeychain: useKeychain, fromKeychainEnabled: fromKeychainEnabled)
        }
    ) {
        self.appSettings = appSettings
        self.serverStore = serverStore
        self.permissionService = permissionService
        self.eventsPermissionService = eventsPermissionService
        self.contactsPermissionService = contactsPermissionService
        self.locationPermissionService = locationPermissionService
        self.launchAtLoginService = launchAtLoginService
        self.migrateTokenStorage = migrateTokenStorage
    }

    var endpointURL: String {
        "http://127.0.0.1:\(appSettings.mcpPort)/mcp"
    }

    func applyUsageLoggingChange(_ enabled: Bool) async {
        appSettings.usageLoggingEnabled = enabled
        await serverStore.setUsageLoggingEnabled(enabled)
    }

    func applyKeychainStorageChange(_ useKeychain: Bool) async {
        guard useKeychain != appSettings.useKeychainForAPIKey else { return }

        let previousUseKeychain = appSettings.useKeychainForAPIKey
        let wasRunning = serverStore.runState == .running

        do {
            try migrateTokenStorage(useKeychain, previousUseKeychain)
        } catch {
            return
        }

        if wasRunning {
            await serverStore.stopServer()
        }

        appSettings.useKeychainForAPIKey = useKeychain
        await serverStore.reconfigureTokenStore(useKeychain: useKeychain)

        if appSettings.mcpEnabled, wasRunning {
            await serverStore.startServer(
                port: appSettings.mcpPort,
                enabledCapabilities: serverEnabledCapabilities,
                usageLoggingEnabled: appSettings.usageLoggingEnabled
            )
        } else {
            await serverStore.refreshBearerToken()
        }
    }

    func refreshUsageAuditEntries() async {
        let entries = await serverStore.usageAuditEntries()
        usageAuditEntries = Array(entries.reversed())
    }

    func usageAuditExportJSON() -> String {
        UsageAuditExport.jsonString(from: Array(usageAuditEntries.reversed()))
    }

    func applyMCPEnabledChange(_ enabled: Bool) async {
        appSettings.mcpEnabled = enabled
        tokenResetNotice = nil

        if enabled {
            await serverStore.startServer(
                port: appSettings.mcpPort,
                enabledCapabilities: serverEnabledCapabilities,
                usageLoggingEnabled: appSettings.usageLoggingEnabled
            )
        } else {
            await serverStore.stopServer()
        }
    }

    func applyPortChange(_ port: UInt16) async {
        guard port != appSettings.mcpPort else { return }

        appSettings.mcpPort = port
        tokenResetNotice = nil

        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: port,
            enabledCapabilities: serverEnabledCapabilities,
            usageLoggingEnabled: appSettings.usageLoggingEnabled
        )
    }

    func copyBearerToken() -> String? {
        serverStore.bearerToken
    }

    func resetBearerToken() async {
        tokenResetNotice = nil
        let wasRunning = serverStore.runState == .running
        await serverStore.resetBearerToken(
            port: appSettings.mcpPort,
            enabledCapabilities: serverEnabledCapabilities,
            restartIfRunning: appSettings.mcpEnabled,
            usageLoggingEnabled: appSettings.usageLoggingEnabled
        )
        guard serverStore.lastError == nil else { return }
        tokenResetNotice = tokenResetNoticeMessage(
            mcpEnabled: appSettings.mcpEnabled,
            wasRunning: wasRunning
        )
    }

    func applySavedCapabilities(
        remindersAuthorized: Bool,
        eventsAuthorized: Bool,
        contactsAuthorized: Bool,
        locationAuthorized: Bool
    ) async {
        tokenResetNotice = nil
        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: remindersAuthorized,
                eventsAuthorized: eventsAuthorized,
                contactsAuthorized: contactsAuthorized,
                locationAuthorized: locationAuthorized
            ),
            usageLoggingEnabled: appSettings.usageLoggingEnabled
        )
    }

    private var serverEnabledCapabilities: [String] {
        appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: permissionService.currentStatus().grantsReadAccess,
            eventsAuthorized: eventsPermissionService.currentStatus().grantsReadAccess,
            contactsAuthorized: contactsPermissionService.currentStatus().grantsReadAccess,
            locationAuthorized: locationPermissionService.currentStatus().grantsReadAccess
        )
    }

    private func tokenResetNoticeMessage(mcpEnabled: Bool, wasRunning: Bool) -> String {
        if mcpEnabled, wasRunning {
            "Server restarted with a new token. Update your MCP client."
        } else {
            "Bearer token reset. Update your MCP client with the new token."
        }
    }

    func applyLaunchAtLoginChange(_ enabled: Bool) async {
        launchAtLoginError = nil
        do {
            if enabled {
                try launchAtLoginService.register()
                appSettings.launchAtLogin = true
            } else {
                try launchAtLoginService.unregister()
                appSettings.launchAtLogin = false
            }
        } catch {
            launchAtLoginError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Reconciles persisted launch-at-login preference with system registration status.
    /// Invoked from `AppleBridgeApp.init()` only — not from SwiftUI view lifecycle.
    func performLaunchAtLoginReconcileIfNeeded() async {
        guard !didPerformLaunchAtLoginReconcile else { return }
        didPerformLaunchAtLoginReconcile = true
        let systemRegistered = launchAtLoginService.isRegistered
        if appSettings.launchAtLogin != systemRegistered {
            appSettings.launchAtLogin = systemRegistered
        }
        launchAtLoginError = nil
    }

    /// Restores the MCP server once per process launch when `mcpEnabled` was persisted.
    /// Invoked from `AppleBridgeApp.init()` only — not from any SwiftUI view lifecycle.
    func performLaunchRestoreIfNeeded() async {
        guard !didPerformLaunchRestore else { return }
        didPerformLaunchRestore = true

        guard appSettings.mcpEnabled else { return }

        await serverStore.startServer(
            port: appSettings.mcpPort,
            enabledCapabilities: serverEnabledCapabilities,
            usageLoggingEnabled: appSettings.usageLoggingEnabled
        )
    }
}

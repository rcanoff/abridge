import AppKit
import SwiftUI

@main
struct AppleBridgeApp: App {
    /// True when injected into the test runner (legacy TEST_HOST) or xcodebuild test.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
    }

    @State private var store: AppStore
    @State private var serverStore: ServerStore
    @State private var appSettings: AppSettings
    @State private var permissionsStore: PermissionsStore
    @State private var settingsStore: SettingsStore

    init() {
        if AppLaunchGuard.evaluate(
            isRunningUnitTests: Self.isRunningUnitTests,
            singleInstanceChecker: RunningApplicationInstanceChecker()
        ) == .exitDuplicate {
            exit(0)
        }

        let appSettings = AppSettings()
        let serverStore = ServerStore(
            serverService: ServerService(
                tokenStore: BearerTokenStoreFactory.make(useKeychain: appSettings.useKeychainForAPIKey)
            )
        )
        let permissionService = RemindersPermissionService()
        let store = AppStore(permissionService: permissionService)
        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            permissionService: permissionService
        )
        _appSettings = State(initialValue: appSettings)
        _serverStore = State(initialValue: serverStore)
        _permissionsStore = State(initialValue: PermissionsStore(appSettings: appSettings))
        _settingsStore = State(initialValue: settingsStore)
        _store = State(initialValue: store)

        guard !Self.isRunningUnitTests else { return }

        AppleBridgeAppLaunchSupport.scheduleLaunchRestore(
            settingsStore: settingsStore,
            serverStore: serverStore
        )
    }

    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            MenuBarPopoverView(store: store, serverStore: serverStore)
                .onAppear {
                    refreshAppAndServerState()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    refreshAppAndServerState()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsWindowView(
                settingsStore: settingsStore,
                permissionsStore: permissionsStore,
                serverStore: serverStore,
                appStore: store
            )
        }
        .defaultSize(width: 600, height: 460)
    }

    @MainActor
    private func refreshAppAndServerState() {
        guard !Self.isRunningUnitTests else { return }
        store.refreshStatus()
        Task {
            await refreshServerStateFromService()
        }
    }

    @MainActor
    private func refreshServerStateFromService() async {
        guard !Self.isRunningUnitTests else { return }
        await serverStore.refreshBearerToken()
        await serverStore.refreshStatus()
    }
}

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
        let dependencies = Self.makeDefaultLaunchDependencies()
        self.init(
            isRunningUnitTests: Self.isRunningUnitTests,
            singleInstanceChecker: dependencies.singleInstanceChecker,
            storeMaker: dependencies.storeMaker
        )
    }

    /// Production wiring used by the no-arg `init()`; exposed for tests verifying shipped dependencies.
    static func makeDefaultLaunchDependencies() -> (
        singleInstanceChecker: any SingleInstanceChecking,
        storeMaker: any AppleBridgeAppStoreMaking
    ) {
        (
            singleInstanceChecker: RunningApplicationInstanceChecker(),
            storeMaker: ProductionAppleBridgeAppStoreMaker()
        )
    }

    init(
        isRunningUnitTests: Bool,
        singleInstanceChecker: any SingleInstanceChecking,
        storeMaker: any AppleBridgeAppStoreMaking
    ) {
        switch AppleBridgeAppBootstrap.performEntry(
            isRunningUnitTests: isRunningUnitTests,
            singleInstanceChecker: singleInstanceChecker,
            storeMaker: storeMaker
        ) {
        case .exitDuplicate:
            exit(0)
        case let .continued(stores):
            _appSettings = State(initialValue: stores.appSettings)
            _serverStore = State(initialValue: stores.serverStore)
            _permissionsStore = State(initialValue: stores.permissionsStore)
            _settingsStore = State(initialValue: stores.settingsStore)
            _store = State(initialValue: stores.store)

            guard !isRunningUnitTests else { return }

            AppleBridgeAppLaunchSupport.scheduleLaunchRestore(
                settingsStore: stores.settingsStore,
                serverStore: stores.serverStore
            )
        }
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

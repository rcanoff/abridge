import AppKit
import SwiftUI

@main
struct ABridgeApp: App {
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
    @State private var calendarSharingStore: CalendarSharingStore
    @State private var updaterService: SparkleUpdaterService
    private let appQuitter: any AppQuitting

    init() {
        let dependencies = Self.makeDefaultLaunchDependencies()
        self.init(
            isRunningUnitTests: Self.isRunningUnitTests,
            singleInstanceChecker: dependencies.singleInstanceChecker,
            storeMaker: dependencies.storeMaker,
            appQuitter: dependencies.appQuitter
        )
    }

    /// Production wiring used by the no-arg `init()`; exposed for tests verifying shipped dependencies.
    static func makeDefaultLaunchDependencies() -> ABridgeLaunchDependencies {
        ABridgeLaunchDependencies(
            singleInstanceChecker: RunningApplicationInstanceChecker(),
            storeMaker: ProductionABridgeAppStoreMaker(),
            appQuitter: NSApplicationQuitter()
        )
    }

    init(
        isRunningUnitTests: Bool,
        singleInstanceChecker: any SingleInstanceChecking,
        storeMaker: any ABridgeAppStoreMaking,
        appQuitter: any AppQuitting = NSApplicationQuitter()
    ) {
        self.appQuitter = appQuitter
        switch ABridgeAppBootstrap.performEntry(
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
            _calendarSharingStore = State(initialValue: stores.calendarSharingStore)
            _store = State(initialValue: stores.store)
            _updaterService = State(initialValue: SparkleUpdaterService(startsUpdater: !isRunningUnitTests))

            guard !isRunningUnitTests else { return }

            ABridgeAppLaunchSupport.scheduleLaunchRestore(
                settingsStore: stores.settingsStore,
                serverStore: stores.serverStore
            )
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarNativeMenuView(
                serverStore: serverStore,
                settingsStore: settingsStore,
                updaterService: updaterService,
                appQuitter: appQuitter
            )
            .onAppear {
                refreshAppAndServerState()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )) { _ in
                refreshAppAndServerState()
            }
        } label: {
            Image("MenuBarMark")
                .renderingMode(.template)
                .accessibilityLabel("ABridge")
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsWindowView(
                settingsStore: settingsStore,
                permissionsStore: permissionsStore,
                serverStore: serverStore,
                appStore: store,
                calendarSharingStore: calendarSharingStore
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

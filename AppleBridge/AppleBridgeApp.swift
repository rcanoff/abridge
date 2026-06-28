import AppKit
import SwiftUI

@main
struct AppleBridgeApp: App {
    @State private var store = AppStore()
    @State private var serverStore = ServerStore()
    @State private var appSettings = AppSettings()
    @State private var permissionsStore: PermissionsStore
    @State private var settingsStore: SettingsStore

    init() {
        let appSettings = AppSettings()
        let serverStore = ServerStore()
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)
        _appSettings = State(initialValue: appSettings)
        _serverStore = State(initialValue: serverStore)
        _permissionsStore = State(initialValue: PermissionsStore(appSettings: appSettings))
        _settingsStore = State(initialValue: settingsStore)
        _store = State(initialValue: AppStore())

        // Restore persisted MCP server at process launch. MenuBarExtra content is not
        // mounted until the popover opens, so this must not live in view onAppear.
        Task(priority: .userInitiated) { @MainActor in
            await settingsStore.performLaunchRestoreIfNeeded()
            await serverStore.refreshBearerToken()
            await serverStore.refreshStatus()
        }
    }

    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            MenuBarPopoverView(store: store, serverStore: serverStore)
                .onAppear {
                    store.refreshStatus()
                    Task {
                        await serverStore.refreshBearerToken()
                        await serverStore.refreshStatus()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    store.refreshStatus()
                    Task {
                        await serverStore.refreshBearerToken()
                        await serverStore.refreshStatus()
                    }
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
}

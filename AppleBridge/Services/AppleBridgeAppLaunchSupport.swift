import Foundation

enum AppleBridgeAppLaunchSupport {
    @MainActor
    static func scheduleLaunchRestore(
        settingsStore: SettingsStore,
        serverStore: ServerStore
    ) {
        Task(priority: .userInitiated) { @MainActor in
            await settingsStore.performLaunchAtLoginReconcileIfNeeded()
            await settingsStore.performLaunchRestoreIfNeeded()
            await serverStore.refreshBearerToken()
            await serverStore.refreshStatus()
        }
    }
}
import Foundation

enum AppleBridgeAppLaunchSupport {
    @MainActor
    @discardableResult
    static func scheduleLaunchRestore(
        settingsStore: SettingsStore,
        serverStore: ServerStore
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) { @MainActor in
            await settingsStore.performLaunchAtLoginReconcileIfNeeded()
            await settingsStore.performLaunchRestoreIfNeeded()
            await serverStore.refreshBearerToken()
            await serverStore.refreshStatus()
        }
    }
}
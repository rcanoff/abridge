import Foundation

enum AppleBridgeAppBootstrap {
    struct Stores {
        let appSettings: AppSettings
        let serverStore: ServerStore
        let store: AppStore
        let permissionsStore: PermissionsStore
        let settingsStore: SettingsStore
    }

    enum EntryResult {
        case exitDuplicate
        case continued(Stores)
    }

    /// Mirrors `AppleBridgeApp.init()` guard-then-bootstrap sequence for testability.
    @MainActor
    static func performEntry(
        isRunningUnitTests: Bool,
        singleInstanceChecker: any SingleInstanceChecking,
        storeMaker: any AppleBridgeAppStoreMaking = ProductionAppleBridgeAppStoreMaker()
    ) -> EntryResult {
        if AppLaunchGuard.evaluate(
            isRunningUnitTests: isRunningUnitTests,
            singleInstanceChecker: singleInstanceChecker
        ) == .exitDuplicate {
            return .exitDuplicate
        }
        return .continued(storeMaker.makeStores())
    }
}

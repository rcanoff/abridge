import Foundation

enum ABridgeAppBootstrap {
    struct Stores {
        let appSettings: AppSettings
        let serverStore: ServerStore
        let store: AppStore
        let permissionsStore: PermissionsStore
        let settingsStore: SettingsStore
        let calendarSharingStore: CalendarSharingStore
    }

    enum EntryResult {
        case exitDuplicate
        case continued(Stores)
    }

    /// Shipped app entry; `ABridgeApp.init` must delegate here only.
    @MainActor
    static func performEntry(
        isRunningUnitTests: Bool,
        singleInstanceChecker: any SingleInstanceChecking,
        storeMaker: any ABridgeAppStoreMaking = ProductionABridgeAppStoreMaker()
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

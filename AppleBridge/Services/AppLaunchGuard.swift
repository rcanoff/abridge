import Foundation

enum AppLaunchGuard {
    enum Action: Equatable {
        case continueLaunch
        case exitDuplicate
    }

    static func evaluate(
        isRunningUnitTests: Bool,
        singleInstanceChecker: any SingleInstanceChecking
    ) -> Action {
        guard !isRunningUnitTests else { return .continueLaunch }
        guard singleInstanceChecker.isDuplicateLaunch() else { return .continueLaunch }
        return .exitDuplicate
    }
}
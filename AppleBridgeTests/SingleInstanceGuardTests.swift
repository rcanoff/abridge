@testable import AppleBridge
import Foundation
import Testing

@Suite("SingleInstanceGuard")
struct SingleInstanceGuardTests {
    @Test
    @MainActor
    func performEntrySkipsStoreBootstrapOnDuplicate() {
        let storeMaker = MockAppleBridgeAppStoreMaker()

        let result = AppleBridgeAppBootstrap.performEntry(
            isRunningUnitTests: false,
            singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: true),
            storeMaker: storeMaker
        )

        guard case .exitDuplicate = result else {
            Issue.record("Expected exitDuplicate, got \(result)")
            return
        }
        #expect(storeMaker.makeStoresCallCount == 0)
    }

    @Test
    @MainActor
    func appInitBootstrapsStoresOnContinuePath() {
        let storeMaker = MockAppleBridgeAppStoreMaker()

        _ = AppleBridgeApp(
            isRunningUnitTests: true,
            singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: false),
            storeMaker: storeMaker
        )

        #expect(storeMaker.makeStoresCallCount == 1)
    }

    @Test
    func appInitExitsOnDuplicateLaunch() async {
        await #expect(processExitsWith: .success) {
            _ = AppleBridgeApp(
                isRunningUnitTests: false,
                singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: true),
                storeMaker: MockAppleBridgeAppStoreMaker()
            )
        }
    }

    @Test
    @MainActor
    func defaultLaunchDependenciesUseProductionTypes() {
        let dependencies = AppleBridgeApp.makeDefaultLaunchDependencies()

        #expect(dependencies.singleInstanceChecker is RunningApplicationInstanceChecker)
        #expect(dependencies.storeMaker is ProductionAppleBridgeAppStoreMaker)
    }

    @Test
    func shippedProductionInitExitsOnDuplicateWithRunningApplicationChecker() async {
        await #expect(processExitsWith: .success) {
            _ = AppleBridgeApp(
                isRunningUnitTests: false,
                singleInstanceChecker: RunningApplicationInstanceChecker(
                    hasOtherRunningInstance: { _, _ in true }
                ),
                storeMaker: MockAppleBridgeAppStoreMaker()
            )
        }
    }

    @Test
    func productionCheckerDetectsDuplicateWhenOtherInstancePresent() {
        let checker = RunningApplicationInstanceChecker(
            hasOtherRunningInstance: { _, _ in true }
        )
        let action = AppLaunchGuard.evaluate(isRunningUnitTests: false, singleInstanceChecker: checker)

        #expect(action == .exitDuplicate)
    }

    @Test
    @MainActor
    func performEntryBootstrapsStoresWhenNotDuplicate() {
        let storeMaker = MockAppleBridgeAppStoreMaker()

        let result = AppleBridgeAppBootstrap.performEntry(
            isRunningUnitTests: false,
            singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: false),
            storeMaker: storeMaker
        )

        guard case .continued = result else {
            Issue.record("Expected continued, got \(result)")
            return
        }
        #expect(storeMaker.makeStoresCallCount == 1)
    }

    @Test
    func evaluateContinuesWhenNotDuplicate() {
        let checker = MockSingleInstanceChecker()

        let action = AppLaunchGuard.evaluate(isRunningUnitTests: false, singleInstanceChecker: checker)

        #expect(action == .continueLaunch)
    }

    @Test
    func evaluateExitsWhenDuplicateAndNotUnitTests() {
        let checker = MockSingleInstanceChecker()
        checker.isDuplicate = true

        let action = AppLaunchGuard.evaluate(isRunningUnitTests: false, singleInstanceChecker: checker)

        #expect(action == .exitDuplicate)
    }

    @Test
    func evaluateContinuesDuringUnitTestsEvenWhenDuplicate() {
        let checker = MockSingleInstanceChecker()
        checker.isDuplicate = true

        let action = AppLaunchGuard.evaluate(isRunningUnitTests: true, singleInstanceChecker: checker)

        #expect(action == .continueLaunch)
    }

    @Test
    func runningApplicationCheckerTreatsOtherInstanceAsDuplicate() {
        let checker = RunningApplicationInstanceChecker(
            bundleIdentifier: { "com.applebridge.AppleBridge" },
            currentProcessIdentifier: { 100 },
            hasOtherRunningInstance: { _, _ in true }
        )

        #expect(checker.isDuplicateLaunch())
    }

    @Test
    func runningApplicationCheckerTreatsOnlyCurrentInstanceAsNotDuplicate() {
        let checker = RunningApplicationInstanceChecker(
            bundleIdentifier: { "com.applebridge.AppleBridge" },
            currentProcessIdentifier: { 100 },
            hasOtherRunningInstance: { _, _ in false }
        )

        #expect(checker.isDuplicateLaunch() == false)
    }

    @Test
    @MainActor
    func launchRestoreSkippedWhenGuardWouldExitDuplicate() async throws {
        let suiteName = "SingleInstanceGuardTests.launchRestoreSkipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        let action = AppLaunchGuard.evaluate(
            isRunningUnitTests: false,
            singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: true)
        )

        if action == .continueLaunch {
            AppleBridgeAppLaunchSupport.scheduleLaunchRestore(
                settingsStore: settingsStore,
                serverStore: serverStore
            )
        }

        #expect(action == .exitDuplicate)
        #expect(await mock.startCallCount == 0)
    }

    @Test
    @MainActor
    func launchRestoreRunsWhenGuardContinues() async throws {
        let suiteName = "SingleInstanceGuardTests.launchRestoreRuns"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let settingsStore = SettingsStore(appSettings: appSettings, serverStore: serverStore)

        let action = AppLaunchGuard.evaluate(
            isRunningUnitTests: false,
            singleInstanceChecker: MockSingleInstanceChecker(isDuplicate: false)
        )

        if action == .continueLaunch {
            let launchTask = AppleBridgeAppLaunchSupport.scheduleLaunchRestore(
                settingsStore: settingsStore,
                serverStore: serverStore
            )
            await launchTask.value
        }

        #expect(action == .continueLaunch)
        #expect(await mock.startCallCount == 1)
    }
}

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
    func runningApplicationCheckerTreatsCountGreaterThanOneAsDuplicate() {
        let checker = RunningApplicationInstanceChecker(
            bundleIdentifier: { "com.applebridge.AppleBridge" },
            runningApplicationCount: { _ in 2 }
        )

        #expect(checker.isDuplicateLaunch())
    }

    @Test
    func runningApplicationCheckerTreatsSingleInstanceAsNotDuplicate() {
        let checker = RunningApplicationInstanceChecker(
            bundleIdentifier: { "com.applebridge.AppleBridge" },
            runningApplicationCount: { _ in 1 }
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

import Foundation
import Testing
@testable import AppleBridge

@Suite("ServerConfigCapabilities")
struct ServerConfigCapabilitiesTests {
    @Test
    @MainActor
    func startPassesEnabledCapabilities() async {
        let mock = MockServerService()
        let appSettings = AppSettings(defaults: UserDefaults(suiteName: "ServerConfigCapabilitiesTests")!)
        appSettings.saveCapabilityIDs(["read"])
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: appSettings.enabledMCPCapabilityIDs)

        #expect(await mock.lastEnabledCapabilities == ["eventkit.reminders.read"])
    }
}
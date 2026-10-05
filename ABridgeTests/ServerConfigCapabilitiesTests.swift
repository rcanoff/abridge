@testable import ABridge
import Foundation
import Testing

@Suite("ServerConfigCapabilities")
struct ServerConfigCapabilitiesTests {
    @Test
    @MainActor
    func startPassesEnabledCapabilities() async throws {
        let mock = MockServerService()
        let appSettings = try AppSettings(defaults: #require(UserDefaults(suiteName: "ServerConfigCapabilitiesTests")))
        appSettings.saveCapabilityIDs(["read"])
        let store = ServerStore(serverService: mock)

        await store.startServer(port: 3020, enabledCapabilities: appSettings.enabledMCPCapabilityIDs)

        #expect(await mock.lastEnabledCapabilities == ["eventkit.reminders.read"])
    }
}

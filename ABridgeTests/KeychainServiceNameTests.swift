@testable import ABridge
import Testing

@Suite("Bearer token keychain name")
struct KeychainServiceNameTests {
    @Test
    func releaseBundleKeepsTheExistingServiceName() {
        let name = BearerTokenServiceName.serviceName(bundleIdentifier: "io.github.rcanoff.ABridge")
        #expect(name == "io.github.rcanoff.ABridge.mcp-bearer-token")
        #expect(name == BearerTokenServiceName.release)
    }

    @Test
    func debugBundleGetsItsOwnItem() {
        let name = BearerTokenServiceName.serviceName(bundleIdentifier: "io.github.rcanoff.ABridge.debug")
        #expect(name == "io.github.rcanoff.ABridge.debug.mcp-bearer-token")
        #expect(name != BearerTokenServiceName.release)
    }
}

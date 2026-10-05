@testable import ABridge
import Foundation

@MainActor
final class MockLaunchAtLoginService: LaunchAtLoginManaging {
    var isRegistered = false
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        isRegistered = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        isRegistered = false
    }
}

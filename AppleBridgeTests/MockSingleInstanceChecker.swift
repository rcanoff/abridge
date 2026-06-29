@testable import AppleBridge
import Foundation

final class MockSingleInstanceChecker: SingleInstanceChecking, @unchecked Sendable {
    var isDuplicate: Bool

    init(isDuplicate: Bool = false) {
        self.isDuplicate = isDuplicate
    }

    func isDuplicateLaunch() -> Bool {
        isDuplicate
    }
}
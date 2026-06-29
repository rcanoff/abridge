import Foundation

protocol SingleInstanceChecking: Sendable {
    func isDuplicateLaunch() -> Bool
}
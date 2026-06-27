import Foundation

@MainActor
protocol ServerServing: AnyObject {
    func refreshStatus() -> ServerRunState
    func start(host: String, port: UInt16) throws
    func stop() throws
}
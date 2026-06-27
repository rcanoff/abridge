import AppKit
import Foundation

@MainActor
protocol URLOpening {
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: URLOpening {}

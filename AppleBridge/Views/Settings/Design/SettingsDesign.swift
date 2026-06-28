import SwiftUI

enum SettingsDesign {
    static let popoverSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let glassCornerRadius: CGFloat = 12

    static func symbol(for tab: SettingsTab) -> String {
        switch tab {
        case .mcp:
            "point.3.connected.trianglepath.dotted"
        case .permissions:
            "lock.shield"
        case .diagnostics:
            "waveform.path.ecg"
        }
    }
}

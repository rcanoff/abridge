import AppKit

/// Where ABridge shows its icon: the menu bar, the Dock, or neither.
enum AppIconMode: String, CaseIterable, Identifiable {
    case menuBar
    case dock
    case hidden

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .menuBar: "Menu bar"
        case .dock: "Dock"
        case .hidden: "Hidden"
        }
    }

    var showsMenuBarIcon: Bool {
        self == .menuBar
    }

    /// `.regular` shows the Dock icon; `.accessory` hides it.
    func activationPolicy(isSettingsWindowOpen: Bool) -> NSApplication.ActivationPolicy {
        switch self {
        case .menuBar: .accessory
        case .dock: .regular
        case .hidden: isSettingsWindowOpen ? .regular : .accessory
        }
    }
}

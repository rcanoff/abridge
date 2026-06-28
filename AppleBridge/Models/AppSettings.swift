import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let mcpPort = "mcpPort"
        static let mcpEnabled = "mcpEnabled"
        static let savedCapabilityIDs = "savedCapabilityIDs"
    }

    private let defaults: UserDefaults

    var mcpPort: UInt16 {
        didSet {
            guard mcpPort != oldValue else { return }
            defaults.set(Int(mcpPort), forKey: Keys.mcpPort)
        }
    }

    var mcpEnabled: Bool {
        didSet {
            guard mcpEnabled != oldValue else { return }
            defaults.set(mcpEnabled, forKey: Keys.mcpEnabled)
        }
    }

    private(set) var savedCapabilityIDs: Set<String> {
        didSet {
            defaults.set(Array(savedCapabilityIDs), forKey: Keys.savedCapabilityIDs)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedPort = defaults.integer(forKey: Keys.mcpPort)
        if let port = UInt16(exactly: storedPort), port > 0 {
            mcpPort = port
        } else {
            mcpPort = 3020
        }
        mcpEnabled = defaults.bool(forKey: Keys.mcpEnabled)

        if let stored = defaults.stringArray(forKey: Keys.savedCapabilityIDs) {
            savedCapabilityIDs = Set(stored)
        } else {
            savedCapabilityIDs = []
        }
    }

    func saveCapabilityIDs(_ ids: Set<String>) {
        savedCapabilityIDs = ids
    }

    var enabledMCPCapabilityIDs: [String] {
        CapabilityCatalog.remindersCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }
}
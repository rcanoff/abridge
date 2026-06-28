import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {
    private enum Keys {
        static let mcpPort = "mcpPort"
        static let mcpEnabled = "mcpEnabled"
        static let usageLoggingEnabled = "usageLoggingEnabled"
        static let launchAtLogin = "launchAtLogin"
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

    var usageLoggingEnabled: Bool {
        didSet {
            guard usageLoggingEnabled != oldValue else { return }
            defaults.set(usageLoggingEnabled, forKey: Keys.usageLoggingEnabled)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
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
        if defaults.object(forKey: Keys.usageLoggingEnabled) != nil {
            usageLoggingEnabled = defaults.bool(forKey: Keys.usageLoggingEnabled)
        } else {
            usageLoggingEnabled = true
        }
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

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
        enabledReminderCapabilityIDs + enabledCalendarCapabilityIDs + enabledEventsCapabilityIDs
    }

    var enabledReminderCapabilityIDs: [String] {
        CapabilityCatalog.remindersCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }

    var enabledCalendarCapabilityIDs: [String] {
        CapabilityCatalog.calendarsCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }

    var enabledEventsCapabilityIDs: [String] {
        CapabilityCatalog.eventsCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }

    func serverEnabledMCPCapabilityIDs(remindersAuthorized: Bool, eventsAuthorized: Bool) -> [String] {
        var capabilities = ["diagnostics.read"]
        if remindersAuthorized {
            capabilities.append(contentsOf: enabledReminderCapabilityIDs)
        }
        if eventsAuthorized {
            capabilities.append(contentsOf: enabledCalendarCapabilityIDs)
            capabilities.append(contentsOf: enabledEventsCapabilityIDs)
        }
        return capabilities
    }
}

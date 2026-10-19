import AppKit
import CoreServices
import Foundation

enum NotesPrivacySettings {
    static let fullDiskAccessURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    static let automationURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
}

enum NotesAutomationPermission {
    static let bundleIdentifier = "com.apple.Notes"

    /// Reads the stored consent without prompting.
    static func determine() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(kAECoreSuite),
            AEEventID(kAEGetData),
            false
        )
    }

    /// Asks Notes for its account count through `osascript`, the same path the Rust JXA writes use,
    /// so macOS shows its consent panel for ABridge. `AEDeterminePermissionToAutomateTarget` with
    /// `askUserIfNeeded` never prompts for this app ("Policy disallows prompt"), and JXA answers
    /// `name()` locally without sending an event. Blocks until the user answers.
    static func sendConsentEvent() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", "Application('Notes').accounts.length"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    @MainActor
    static func launchIfNeeded() async throws {
        let alreadyRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == bundleIdentifier
        }
        guard !alreadyRunning else { return }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

@MainActor
final class NotesAutomationService: NotesAutomationChecking {
    typealias PermissionDeterminer = @Sendable () -> OSStatus
    typealias ConsentEventSender = @Sendable () throws -> Void
    typealias NotesLauncher = @MainActor () async throws -> Void

    private let determinePermission: PermissionDeterminer
    private let sendConsentEvent: ConsentEventSender
    private let launchNotesIfNeeded: NotesLauncher

    init(
        determinePermission: @escaping PermissionDeterminer = NotesAutomationPermission.determine,
        sendConsentEvent: @escaping ConsentEventSender = NotesAutomationPermission.sendConsentEvent,
        launchNotesIfNeeded: @escaping NotesLauncher = NotesAutomationPermission.launchIfNeeded
    ) {
        self.determinePermission = determinePermission
        self.sendConsentEvent = sendConsentEvent
        self.launchNotesIfNeeded = launchNotesIfNeeded
    }

    func currentStatus() -> NotesAutomationStatus {
        NotesAutomationStatusMapper.map(determinePermission())
    }

    func requestAccess() async throws -> NotesAutomationStatus {
        try await launchNotesIfNeeded()
        let sendConsentEvent = sendConsentEvent
        // The event waits while the consent panel is up; keep it off the main actor.
        try await Task.detached {
            try sendConsentEvent()
        }.value
        return currentStatus()
    }
}

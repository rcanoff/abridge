import Foundation

@MainActor
protocol NotesAutomationChecking {
    func currentStatus() -> NotesAutomationStatus
    func requestAccess() async throws -> NotesAutomationStatus
}

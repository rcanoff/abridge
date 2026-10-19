@testable import ABridge
import Foundation

@MainActor
final class MockNotesAutomationService: NotesAutomationChecking {
    var status: NotesAutomationStatus = .denied
    var requestResult: Result<NotesAutomationStatus, Error> = .success(.granted)
    private(set) var requestCallCount = 0

    func currentStatus() -> NotesAutomationStatus {
        status
    }

    func requestAccess() async throws -> NotesAutomationStatus {
        requestCallCount += 1
        let result = try requestResult.get()
        status = result
        return result
    }
}

@testable import ABridge
import Foundation

@MainActor
final class MockNotesFullDiskAccessService: NotesFullDiskAccessChecking {
    var status: NotesFullDiskAccessStatus = .notGranted

    func currentStatus() -> NotesFullDiskAccessStatus {
        status
    }
}

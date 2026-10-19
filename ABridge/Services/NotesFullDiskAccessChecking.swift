import Foundation

@MainActor
protocol NotesFullDiskAccessChecking {
    func currentStatus() -> NotesFullDiskAccessStatus
}

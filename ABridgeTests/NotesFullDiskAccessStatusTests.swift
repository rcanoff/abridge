@testable import ABridge
import Foundation
import Testing

@Suite("NotesFullDiskAccessStatus")
struct NotesFullDiskAccessStatusTests {
    @Test
    func mapOpenedGrantsAccess() {
        let status = NotesFullDiskAccessStatusMapper.map(.opened)
        #expect(status == .granted)
        #expect(status.grantsAccess)
    }

    @Test
    func mapPermissionErrorsAreNotGranted() {
        #expect(NotesFullDiskAccessStatusMapper.map(.posixError(EPERM)) == .notGranted)
        #expect(NotesFullDiskAccessStatusMapper.map(.posixError(EACCES)) == .notGranted)
        #expect(NotesFullDiskAccessStatusMapper.map(.posixError(EPERM)).grantsAccess == false)
    }

    @Test
    func mapMissingFileIsNotesNotSetUp() {
        let status = NotesFullDiskAccessStatusMapper.map(.posixError(ENOENT))
        #expect(status == .notSetUp)
        #expect(status.displayName == "Notes not set up")
    }

    @Test
    func mapUnexpectedErrnoIsUnknown() {
        #expect(NotesFullDiskAccessStatusMapper.map(.posixError(EIO)) == .unknown)
    }

    @Test
    func openerReportsOpenedMissingAndUnreadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory
        let readable = directory.appending(path: "notes-probe-\(UUID().uuidString)")
        let missing = directory.appending(path: "notes-missing-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(atPath: readable.path, contents: Data("note".utf8)))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: readable.path)
            try? FileManager.default.removeItem(at: readable)
        }

        #expect(NotesStoreOpener.probe(readable) == .opened)
        #expect(NotesFullDiskAccessStatusMapper.map(NotesStoreOpener.probe(readable)) == .granted)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: readable.path)
        #expect(NotesStoreOpener.probe(readable) == .posixError(EACCES))

        #expect(NotesStoreOpener.probe(missing) == .posixError(ENOENT))
        #expect(NotesFullDiskAccessStatusMapper.map(NotesStoreOpener.probe(missing)) == .notSetUp)
    }

    @Test
    @MainActor
    func serviceMapsInjectedProbe() {
        let service = NotesFullDiskAccessService(storeURL: URL(filePath: "/tmp/unused-notes-store")) { _ in
            .posixError(EPERM)
        }
        #expect(service.currentStatus() == .notGranted)
    }
}

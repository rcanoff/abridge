import Foundation

enum NotesStoreLocation {
    /// Notes' Core Data store. TCC hides this file until the app has Full Disk Access.
    static var noteStoreSQLite: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(
                path: "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
                directoryHint: .notDirectory
            )
    }
}

enum NotesStoreOpener {
    /// `FileManager.isReadableFile` is not enough under TCC. Opening read-only is the probe.
    static func probe(_ url: URL) -> NotesStoreProbeOutcome {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return .posixError(ENOENT) }
            let fileDescriptor = open(path, O_RDONLY)
            if fileDescriptor >= 0 {
                close(fileDescriptor)
                return .opened
            }
            return .posixError(errno)
        }
    }
}

@MainActor
final class NotesFullDiskAccessService: NotesFullDiskAccessChecking {
    private let storeURL: URL
    private let probe: (URL) -> NotesStoreProbeOutcome

    init(
        storeURL: URL = NotesStoreLocation.noteStoreSQLite,
        probe: @escaping (URL) -> NotesStoreProbeOutcome = NotesStoreOpener.probe
    ) {
        self.storeURL = storeURL
        self.probe = probe
    }

    func currentStatus() -> NotesFullDiskAccessStatus {
        NotesFullDiskAccessStatusMapper.map(probe(storeURL))
    }
}

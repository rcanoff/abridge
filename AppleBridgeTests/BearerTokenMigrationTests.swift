@testable import AppleBridge
import Foundation
import Testing

@Suite("BearerTokenMigration")
struct BearerTokenMigrationTests {
    @Test
    func migrateCopiesTokenFromSourceToDestination() throws {
        let source = MockBearerTokenStore(storedToken: "migrate-me")
        let destination = MockBearerTokenStore()

        try BearerTokenMigrator.migrate(from: source, to: destination)

        #expect(try destination.loadBearerToken() == "migrate-me")
        #expect(try source.loadBearerToken() == nil)
    }

    @Test
    func migrateNoOpWhenSourceHasNoToken() throws {
        let source = MockBearerTokenStore()
        let destination = MockBearerTokenStore(storedToken: "keep-me")

        try BearerTokenMigrator.migrate(from: source, to: destination)

        #expect(try destination.loadBearerToken() == "keep-me")
    }

    @Test
    func migrateBetweenKeychainAndFileModesUsesCorrectStores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BearerTokenMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("api-key")
        let fileStore = FileBearerTokenStore(fileURL: fileURL)
        let keychainStore = MockBearerTokenStore(storedToken: "key-from-mock")

        try BearerTokenMigrator.migrate(from: keychainStore, to: fileStore)

        #expect(try fileStore.loadBearerToken() == "key-from-mock")
        #expect(try keychainStore.loadBearerToken() == nil)
    }
}

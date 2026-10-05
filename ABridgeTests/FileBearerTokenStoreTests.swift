@testable import ABridge
import Foundation
import Testing

@Suite("FileBearerTokenStore")
struct FileBearerTokenStoreTests {
    private func makeTempStore() throws -> (FileBearerTokenStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBearerTokenStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("api-key")
        return (FileBearerTokenStore(fileURL: fileURL), directory)
    }

    @Test
    func loadOrCreateCreatesAndPersistsToken() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try store.loadOrCreateBearerToken()
        #expect(first.hasPrefix(APIKeyFormatting.livePrefix))

        let second = try store.loadOrCreateBearerToken()
        #expect(first == second)
    }

    @Test
    func loadOrCreateReturnsExistingToken() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.saveBearerToken("existing-file-token")

        let loaded = try store.loadOrCreateBearerToken()
        #expect(loaded == "existing-file-token")
    }

    @Test
    func rotateBearerTokenReplacesStoredToken() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.saveBearerToken("original-token")

        let rotated = try store.rotateBearerToken()

        #expect(rotated != "original-token")
        #expect(rotated.hasPrefix(APIKeyFormatting.livePrefix))
        #expect(try store.loadOrCreateBearerToken() == rotated)
    }

    @Test
    func saveBearerTokenSetsRestrictivePermissions() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.saveBearerToken("permission-test-token")

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURLForTesting.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.uint16Value == 0o600)
    }

    @Test
    func deleteBearerTokenRemovesFile() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.saveBearerToken("delete-me")
        try store.deleteBearerToken()

        #expect(FileManager.default.fileExists(atPath: store.fileURLForTesting.path) == false)
    }
}

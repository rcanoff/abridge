import Foundation

struct FileBearerTokenError: Error, Equatable {
    let message: String
}

struct FileBearerTokenStore: BearerTokenPersisting {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("ABridge", isDirectory: true)
            .appendingPathComponent("api-key", isDirectory: false)
    }

    var fileURLForTesting: URL {
        fileURL
    }

    func loadOrCreateBearerToken() throws -> String {
        if let existing = try loadBearerToken() {
            return existing
        }

        let token = try Self.generateToken()
        try saveBearerToken(token)
        return token
    }

    func rotateBearerToken() throws -> String {
        try deleteBearerToken()
        return try loadOrCreateBearerToken()
    }

    func loadBearerToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw FileBearerTokenError(message: "invalid token data in file")
        }
        return token
    }

    func saveBearerToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw FileBearerTokenError(message: "token is not valid UTF-8")
        }

        try Self.ensureDirectoryExists(for: fileURL)
        try data.write(to: fileURL, options: .atomic)
        try Self.setRestrictivePermissions(at: fileURL)
    }

    func deleteBearerToken() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func ensureDirectoryExists(for fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func setRestrictivePermissions(at fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
    }

    private static func generateToken() throws -> String {
        try APIKeyFormatting.generateAPIKey()
    }
}

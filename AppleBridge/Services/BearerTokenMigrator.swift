import Foundation

enum BearerTokenMigrator {
    static func migrate(from source: any BearerTokenPersisting, to destination: any BearerTokenPersisting) throws {
        guard let token = try source.loadBearerToken() else { return }
        try destination.saveBearerToken(token)
        try source.deleteBearerToken()
    }

    static func migrate(useKeychain: Bool, fromKeychainEnabled: Bool) throws {
        guard useKeychain != fromKeychainEnabled else { return }

        let source = BearerTokenStoreFactory.makePersisting(useKeychain: fromKeychainEnabled)
        let destination = BearerTokenStoreFactory.makePersisting(useKeychain: useKeychain)
        try migrate(from: source, to: destination)
    }
}

import Foundation

enum BearerTokenStoreFactory {
    static func make(useKeychain: Bool) -> any BearerTokenStoring {
        if useKeychain {
            KeychainService()
        } else {
            FileBearerTokenStore()
        }
    }

    static func makePersisting(useKeychain: Bool) -> any BearerTokenPersisting {
        if useKeychain {
            KeychainService()
        } else {
            FileBearerTokenStore()
        }
    }
}

import Foundation
import Security

struct KeychainError: Error, Equatable {
    let message: String
}

protocol BearerTokenStoring: Sendable {
    func loadOrCreateBearerToken() throws -> String
    func rotateBearerToken() throws -> String
}

struct KeychainService: BearerTokenStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.applebridge.AppleBridge.mcp-bearer-token",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreateBearerToken() throws -> String {
        if let existing = try loadBearerToken() {
            return existing
        }

        let token = Self.generateToken()
        try saveBearerToken(token)
        return token
    }

    func rotateBearerToken() throws -> String {
        try deleteBearerToken()
        return try loadOrCreateBearerToken()
    }

    func loadBearerToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty
            else {
                throw KeychainError(message: "invalid token data in keychain")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(message: "keychain read failed (status \(status))")
        }
    }

    func saveBearerToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError(message: "token is not valid UTF-8")
        }

        let updateAttributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery()
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(message: "keychain write failed (status \(addStatus))")
            }
        default:
            throw KeychainError(message: "keychain update failed (status \(updateStatus))")
        }
    }

    func deleteBearerToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(message: "keychain delete failed (status \(status))")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func generateToken() -> String {
        APIKeyFormatting.generateAPIKey()
    }
}

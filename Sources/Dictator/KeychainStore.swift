import Foundation
import Security

enum KeychainStore {
    private static let service = "com.fuzzyhead.Ramblr"
    private static let legacyService = "com.fuzzyhead.Dictator"

    static func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        delete(account: account, service: service)

        var insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        if let access = noninteractiveAccess() {
            insert[kSecAttrAccess as String] = access
        }

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func load<T: Codable>(_ type: T.Type, account: String) throws -> T? {
        if let value = try load(type, account: account, service: service) {
            return value
        }

        // One-time migration from the old service name / restrictive ACL.
        if let value = try load(type, account: account, service: legacyService) {
            try? save(value, account: account)
            delete(account: account, service: legacyService)
            return value
        }

        return nil
    }

    static func delete(account: String) {
        delete(account: account, service: service)
        delete(account: account, service: legacyService)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        account: String,
        service: String
    ) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Allows this machine to read the item without re-prompting after every ad-hoc re-sign.
    private static func noninteractiveAccess() -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate("Ramblr" as CFString, nil, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

enum OpenAIKeyStore {
    private static let account = "openai-api-key"

    static func read() -> String {
        (try? KeychainStore.load(String.self, account: account)) ?? ""
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: account)
            return
        }
        try? KeychainStore.save(trimmed, account: account)
    }
}

enum GeminiKeyStore {
    private static let account = "gemini-api-key"

    static func read() -> String {
        (try? KeychainStore.load(String.self, account: account)) ?? ""
    }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: account)
            return
        }
        try? KeychainStore.save(trimmed, account: account)
    }
}

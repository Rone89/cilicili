import Foundation
import Security

final class KeychainStore {
    private let service: String
    private let fallbackPrefix: String

    init(service: String = "JKBili.Session") {
        self.service = service
        self.fallbackPrefix = "\(service).Fallback."
    }

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey(key))
            return
        }
        if status != errSecItemNotFound {
            if shouldUseFallback(for: status) {
                UserDefaults.standard.set(value, forKey: fallbackKey(key))
                return
            }
            throw KeychainError.unhandled(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if shouldUseFallback(for: addStatus) {
            UserDefaults.standard.set(value, forKey: fallbackKey(key))
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
        UserDefaults.standard.removeObject(forKey: fallbackKey(key))
    }

    func read(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return UserDefaults.standard.string(forKey: fallbackKey(key))
        }
        if shouldUseFallback(for: status) {
            return UserDefaults.standard.string(forKey: fallbackKey(key))
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey(key))
        if shouldUseFallback(for: status) {
            return
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func fallbackKey(_ key: String) -> String {
        fallbackPrefix + key
    }

    private func shouldUseFallback(for status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
    }
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            return "Keychain error: \(status)"
        }
    }
}

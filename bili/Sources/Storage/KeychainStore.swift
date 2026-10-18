import Foundation
import Security

/// Injectable Security calls keep tests independent of simulator entitlements.
struct KeychainOperations {
    let update: ([String: Any], [String: Any]) -> OSStatus
    let add: ([String: Any]) -> OSStatus
    let read: ([String: Any]) -> (OSStatus, Data?)
    let delete: ([String: Any]) -> OSStatus

    static var system: Self {
        Self(
            update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
            add: { SecItemAdd($0 as CFDictionary, nil) },
            read: { query in
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                return (status, item as? Data)
            },
            delete: { SecItemDelete($0 as CFDictionary) }
        )
    }
}

final class KeychainStore {
    private let service: String
    private let defaults: UserDefaults
    private let operations: KeychainOperations
    private(set) var failureCount = 0
    private(set) var lastFailure: KeychainError?

    init(
        service: String = "JKBili.Session",
        defaults: UserDefaults = .standard,
        operations: KeychainOperations = .system
    ) {
        self.service = service
        self.defaults = defaults
        self.operations = operations
    }

    func save(_ value: String, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Background audio can read after the device's first unlock.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let query = query(for: key)
        let status = operations.update(query, attributes)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = operations.add(addQuery)
            guard addStatus == errSecSuccess else { throw failure(addStatus) }
        } else if status != errSecSuccess {
            throw failure(status)
        }
        // Delete a legacy plaintext copy only after secure persistence succeeds.
        defaults.removeObject(forKey: fallbackKey(key))
    }

    func read(_ key: String) throws -> String? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = operations.read(query)
        if status == errSecItemNotFound {
            guard let legacy = defaults.string(forKey: fallbackKey(key)) else { return nil }
            // A failed migration throws and leaves the original available for retry.
            try save(legacy, for: key)
            return legacy
        }
        guard status == errSecSuccess else { throw failure(status) }
        guard let data, let value = String(data: data, encoding: .utf8) else {
            failureCount += 1
            lastFailure = .invalidData
            throw KeychainError.invalidData
        }
        defaults.removeObject(forKey: fallbackKey(key))
        return value
    }

    func delete(_ key: String) throws {
        let status = operations.delete(query(for: key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status)
        }
        defaults.removeObject(forKey: fallbackKey(key))
    }

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func fallbackKey(_ key: String) -> String { "\(service).Fallback.\(key)" }

    private func failure(_ status: OSStatus) -> KeychainError {
        let error = KeychainError.unhandled(status)
        failureCount += 1
        lastFailure = error
        return error
    }

    #if DEBUG
    /// Explicit opt-in only. Normal Debug launches still use the real Keychain.
    static func inMemory(service: String) -> KeychainStore {
        let memory = MemoryStorage()
        let operations = KeychainOperations(
            update: { query, attributes in
                let key = query[kSecAttrAccount as String] as! String
                guard memory.values[key] != nil else { return errSecItemNotFound }
                memory.values[key] = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            add: { query in
                let values = query
                memory.values[values[kSecAttrAccount as String] as! String] = values[kSecValueData as String] as? Data
                return errSecSuccess
            },
            read: { query in
                let key = query[kSecAttrAccount as String] as! String
                guard let data = memory.values[key] else { return (errSecItemNotFound, nil) }
                return (errSecSuccess, data)
            },
            delete: { query in
                let key = query[kSecAttrAccount as String] as! String
                memory.values[key] = nil
                return errSecSuccess
            }
        )
        return KeychainStore(service: service, operations: operations)
    }

    private final class MemoryStorage {
        var values: [String: Data] = [:]
    }
    #endif
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)
    case invalidData
    case recoveryRequired

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            return "无法访问安全凭据存储（\(status)），请解锁设备后重试；若仍失败，请检查应用签名权限。"
        case .invalidData:
            return "安全凭据存储中的数据无法读取，请重试。"
        case .recoveryRequired:
            return "请先在“我的”页面重试读取账号，再修改登录状态。"
        }
    }
}

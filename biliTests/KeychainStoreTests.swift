import Foundation
import Security
import XCTest
@testable import bili

@MainActor
final class KeychainStoreTests: XCTestCase {
    private let service = "cc.bili.tests.secure-storage"

    func testUpdateEntitlementFailureNeverWritesPlaintext() throws {
        let (store, stub, defaults) = makeStore()
        stub.updateFailure = errSecMissingEntitlement
        XCTAssertThrowsError(try store.save("secret", for: "token"))
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        XCTAssertNil(stub.values["token"])
        XCTAssertEqual(store.failureCount, 1)
    }

    func testAddEntitlementFailureNeverWritesPlaintext() throws {
        let (store, stub, defaults) = makeStore()
        stub.addFailure = errSecMissingEntitlement
        XCTAssertThrowsError(try store.save("secret", for: "token"))
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        XCTAssertEqual(stub.addCalls, 1)
    }

    func testSuccessfulSaveUsesBackgroundAccessibleDeviceOnlyStorage() throws {
        let (store, stub, defaults) = makeStore()
        defaults.set("old", forKey: legacyKey("token"))
        try store.save("new", for: "token")
        XCTAssertEqual(stub.values["token"], Data("new".utf8))
        XCTAssertEqual(stub.lastAccessibility, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        try store.save("updated", for: "token")
        XCTAssertEqual(try store.read("token"), "updated")
    }

    func testLegacyReadMigratesAndRemovesOnlyTheMatchingPlaintextValue() throws {
        let (store, _, defaults) = makeStore()
        defaults.set("legacy", forKey: legacyKey("token"))
        defaults.set("other", forKey: legacyKey("other"))
        XCTAssertEqual(try store.read("token"), "legacy")
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        XCTAssertEqual(defaults.string(forKey: legacyKey("other")), "other")
        XCTAssertEqual(try store.read("token"), "legacy")
    }

    func testFailedMigrationPreservesOriginalAndCanRetry() throws {
        let (store, stub, defaults) = makeStore()
        defaults.set("legacy", forKey: legacyKey("token"))
        stub.addFailure = errSecMissingEntitlement
        XCTAssertThrowsError(try store.read("token"))
        XCTAssertEqual(defaults.string(forKey: legacyKey("token")), "legacy")
        stub.addFailure = nil
        XCTAssertEqual(try store.read("token"), "legacy")
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
    }

    func testSecureValueWinsOverLegacyAndRemovesStaleCopy() throws {
        let (store, stub, defaults) = makeStore()
        stub.values["token"] = Data("secure".utf8)
        defaults.set("obsolete", forKey: legacyKey("token"))
        XCTAssertEqual(try store.read("token"), "secure")
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        XCTAssertEqual(stub.addCalls, 0)
    }

    func testReadFailureDoesNotReturnOrDeleteLegacyPlaintext() throws {
        let (store, stub, defaults) = makeStore()
        defaults.set("legacy", forKey: legacyKey("token"))
        stub.readFailures["token"] = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.read("token"))
        XCTAssertEqual(defaults.string(forKey: legacyKey("token")), "legacy")
    }

    func testDeleteFailurePreservesRecoveryCopyUntilSuccessfulRetry() throws {
        let (store, stub, defaults) = makeStore()
        defaults.set("legacy", forKey: legacyKey("token"))
        stub.deleteFailure = errSecMissingEntitlement
        XCTAssertThrowsError(try store.delete("token"))
        XCTAssertEqual(defaults.string(forKey: legacyKey("token")), "legacy")
        stub.deleteFailure = nil
        try store.delete("token")
        XCTAssertNil(defaults.string(forKey: legacyKey("token")))
        XCTAssertNil(try store.read("token"))
    }

    func testInvalidSecureDataIsReportedWithoutRemovingRecoveryCopy() throws {
        let (store, stub, defaults) = makeStore()
        stub.values["token"] = Data([0xFF])
        defaults.set("legacy", forKey: legacyKey("token"))
        XCTAssertThrowsError(try store.read("token"))
        XCTAssertEqual(defaults.string(forKey: legacyKey("token")), "legacy")
        XCTAssertEqual(store.failureCount, 1)
    }

    func testTemporarilyUnreadableAccountDoesNotOverwriteRegistryAndCanRecover() throws {
        let (store, stub, _) = makeStore()
        let original = SessionStore(keychain: store)
        try original.saveLoginCookies(["SESSDATA": "saved", "DedeUserID": "1001"])
        let registry = stub.values["MULTI_ACCOUNT_REGISTRY_V1"]
        stub.readFailures["MULTI_ACCOUNT_1001_COOKIE_HEADER"] = errSecInteractionNotAllowed
        let interrupted = SessionStore(keychain: store)
        XCTAssertNotNil(interrupted.credentialStorageError)
        XCTAssertEqual(stub.values["MULTI_ACCOUNT_REGISTRY_V1"], registry)
        XCTAssertThrowsError(try interrupted.saveLoginCookies(["SESSDATA": "other", "DedeUserID": "2002"]))
        XCTAssertEqual(stub.values["MULTI_ACCOUNT_REGISTRY_V1"], registry)
        stub.readFailures = [:]
        interrupted.retryCredentialStorage()
        XCTAssertNil(interrupted.credentialStorageError)
        XCTAssertEqual(interrupted.sessdata, "saved")
        XCTAssertEqual(interrupted.mainAccountMID, 1001)
    }

    func testLoginSaveFailureDoesNotReplaceActiveCredentials() throws {
        let (store, stub, _) = makeStore()
        let session = SessionStore(keychain: store)
        try session.saveLoginCookies(["SESSDATA": "original", "DedeUserID": "1001"])
        stub.updateFailure = errSecMissingEntitlement
        XCTAssertThrowsError(try session.saveLoginCookies(["SESSDATA": "new", "DedeUserID": "1001"]))
        XCTAssertEqual(session.sessdata, "original")
        XCTAssertTrue(session.credentialSnapshot(for: .main, multiAccountEnabled: true).cookieHeader.contains("SESSDATA=original"))
    }

    func testExplicitMemoryStoreDoesNotTouchSystemKeychainOrPlaintext() throws {
        let store = KeychainStore.inMemory(service: "cc.bili.tests.memory.\(UUID().uuidString)")
        try store.save("memory", for: "token")
        XCTAssertEqual(try store.read("token"), "memory")
        try store.delete("token")
        XCTAssertNil(try store.read("token"))
    }

    private func legacyKey(_ key: String) -> String { "\(service).Fallback.\(key)" }

    private func makeStore() -> (KeychainStore, SecurityStub, UserDefaults) {
        let suite = "cc.bili.tests.keychain.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let stub = SecurityStub()
        return (KeychainStore(service: service, defaults: defaults, operations: stub.operations), stub, defaults)
    }

    @MainActor
    private final class SecurityStub {
        var values: [String: Data] = [:]
        var updateFailure: OSStatus?
        var addFailure: OSStatus?
        var deleteFailure: OSStatus?
        var readFailures: [String: OSStatus] = [:]
        var lastAccessibility: String?
        var addCalls = 0

        var operations: KeychainOperations {
            KeychainOperations(
                update: { [self] query, attributes in
                    if let updateFailure { return updateFailure }
                    let key = query[kSecAttrAccount as String] as! String
                    guard values[key] != nil else { return errSecItemNotFound }
                    values[key] = attributes[kSecValueData as String] as? Data
                    lastAccessibility = attributes[kSecAttrAccessible as String] as? String
                    return errSecSuccess
                },
                add: { [self] query in
                    addCalls += 1
                    if let addFailure { return addFailure }
                    values[query[kSecAttrAccount as String] as! String] = query[kSecValueData as String] as? Data
                    lastAccessibility = query[kSecAttrAccessible as String] as? String
                    return errSecSuccess
                },
                read: { [self] query in
                    let key = query[kSecAttrAccount as String] as! String
                    if let failure = readFailures[key] { return (failure, nil) }
                    guard let data = values[key] else { return (errSecItemNotFound, nil) }
                    return (errSecSuccess, data)
                },
                delete: { [self] query in
                    if let deleteFailure { return deleteFailure }
                    values[query[kSecAttrAccount as String] as! String] = nil
                    return errSecSuccess
                }
            )
        }
    }
}

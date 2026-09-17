import Foundation
import XCTest
@testable import bili

@MainActor
final class MultiAccountSessionTests: XCTestCase {
    func testUploaderDynamicCookiePrefersTheAssignedAccountSession() {
        let cookie = BiliAPIClient.uploaderDynamicCookieHeader(
            isLoggedIn: true,
            authenticatedCookieHeader: "SESSDATA=dynamic-session; DedeUserID=2002",
            anonymousCookieHeader: "buvid3=anonymous-device"
        )

        XCTAssertTrue(cookie.contains("SESSDATA=dynamic-session"))
        XCTAssertFalse(cookie.contains("buvid3=anonymous-device"))
    }

    func testUploaderDynamicCookieFallsBackToAnonymousSessionWhenLoggedOut() {
        let cookie = BiliAPIClient.uploaderDynamicCookieHeader(
            isLoggedIn: false,
            authenticatedCookieHeader: "",
            anonymousCookieHeader: "buvid3=anonymous-device"
        )

        XCTAssertEqual(cookie, "buvid3=anonymous-device")
    }

    func testMultiAccountRoutingIsEnabledByDefaultAndPersistsLegacyFlag() {
        let suiteName = "cc.bili.tests.multi-account.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let initialStore = LibraryStore(userDefaults: defaults)
        XCTAssertTrue(initialStore.multiAccountEnabled)

        initialStore.setMultiAccountExperimentEnabled(true)

        XCTAssertTrue(LibraryStore(userDefaults: defaults).multiAccountExperimentEnabled)
    }

    func testLegacySingleAccountMigratesIntoRegistry() throws {
        let keychain = makeKeychain()
        try keychain.save("legacy-session", for: "SESSDATA")
        try keychain.save("legacy-access", for: "ACCESS_KEY")
        try keychain.save(
            "buvid3=legacy-buvid; DedeUserID=1001; SESSDATA=legacy-session; bili_jct=legacy-csrf",
            for: "LOGIN_COOKIE_HEADER"
        )
        try keychain.save(LoginCredentialKind.appSMS.rawValue, for: "LOGIN_CREDENTIAL_KIND")

        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }

        XCTAssertEqual(store.accounts.map(\.mid), [1001])
        XCTAssertEqual(store.mainAccountMID, 1001)
        XCTAssertEqual(store.playbackAccountMID, 1001)
        XCTAssertEqual(store.dynamicFeedAccountMID, 1001)
        XCTAssertEqual(store.interactionAccountMID, 1001)
        XCTAssertEqual(store.sessdata, "legacy-session")
        XCTAssertEqual(store.accessKey, "legacy-access")
        XCTAssertEqual(store.loginCredentialKind, .appSMS)

        let reloadedStore = SessionStore(keychain: keychain)
        let snapshot = reloadedStore.credentialSnapshot(for: .main, multiAccountEnabled: true)
        XCTAssertEqual(snapshot.accountMID, 1001)
        XCTAssertEqual(snapshot.accessKey, "legacy-access")
        XCTAssertTrue(snapshot.cookieHeader.contains("bili_jct=legacy-csrf"))
    }

    func testStoredRegistryWithoutNewPurposeAssignmentsDefaultsToMain() throws {
        let keychain = makeKeychain()
        try keychain.save(
            """
            {"accounts":[{"mid":1001,"credentialKind":"web"}],"mainAccountMID":1001,"playbackAccountMID":1001,"historyPolicy":"main"}
            """,
            for: "MULTI_ACCOUNT_REGISTRY_V1"
        )
        try keychain.save(
            "buvid3=legacy-buvid; DedeUserID=1001; SESSDATA=legacy-session; bili_jct=legacy-csrf",
            for: "MULTI_ACCOUNT_1001_COOKIE_HEADER"
        )
        try keychain.save(LoginCredentialKind.web.rawValue, for: "MULTI_ACCOUNT_1001_CREDENTIAL_KIND")

        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }

        XCTAssertEqual(store.interactionAccountMID, 1001)
        XCTAssertEqual(store.dynamicFeedAccountMID, 1001)
        XCTAssertEqual(
            store.credentialSnapshot(for: .interaction, multiAccountEnabled: true).accountMID,
            1001
        )
        XCTAssertEqual(
            store.credentialSnapshot(for: .dynamicFeed, multiAccountEnabled: true).accountMID,
            1001
        )
    }

    func testAddingSecondaryAccountDoesNotReplaceMainAccount() throws {
        let store = makeSessionStore()
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)

        let secondary = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "playback-session", csrf: "playback-csrf")
        )

        XCTAssertEqual(secondary.mid, 2002)
        XCTAssertEqual(store.accounts.map(\.mid), [1001, 2002])
        XCTAssertEqual(store.mainAccountMID, 1001)
        XCTAssertEqual(store.playbackAccountMID, 1001)
        XCTAssertEqual(store.dynamicFeedAccountMID, 1001)
        XCTAssertEqual(store.interactionAccountMID, 1001)
        XCTAssertEqual(store.sessdata, "main-session")
    }

    func testExperimentOffAlwaysRoutesAssignedPurposesToMainAccount() throws {
        let store = makeSessionStore()
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "playback-session", csrf: "playback-csrf")
        )
        try store.selectPlaybackAccount(mid: 2002)
        try store.selectDynamicFeedAccount(mid: 2002)
        try store.selectInteractionAccount(mid: 2002)

        let disabledSnapshot = store.credentialSnapshot(
            for: .playback,
            multiAccountEnabled: false
        )
        let enabledSnapshot = store.credentialSnapshot(
            for: .playback,
            multiAccountEnabled: true
        )
        let disabledInteractionSnapshot = store.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: false
        )
        let enabledInteractionSnapshot = store.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: true
        )
        let disabledDynamicFeedSnapshot = store.credentialSnapshot(
            for: .dynamicFeed,
            multiAccountEnabled: false
        )
        let enabledDynamicFeedSnapshot = store.credentialSnapshot(
            for: .dynamicFeed,
            multiAccountEnabled: true
        )

        XCTAssertEqual(disabledSnapshot.accountMID, 1001)
        XCTAssertTrue(disabledSnapshot.cookieHeader.contains("SESSDATA=main-session"))
        XCTAssertEqual(enabledSnapshot.accountMID, 2002)
        XCTAssertTrue(enabledSnapshot.cookieHeader.contains("SESSDATA=playback-session"))
        XCTAssertEqual(disabledInteractionSnapshot.accountMID, 1001)
        XCTAssertTrue(disabledInteractionSnapshot.cookieHeader.contains("SESSDATA=main-session"))
        XCTAssertEqual(enabledInteractionSnapshot.accountMID, 2002)
        XCTAssertTrue(enabledInteractionSnapshot.cookieHeader.contains("SESSDATA=playback-session"))
        XCTAssertEqual(disabledDynamicFeedSnapshot.accountMID, 1001)
        XCTAssertTrue(disabledDynamicFeedSnapshot.cookieHeader.contains("SESSDATA=main-session"))
        XCTAssertEqual(enabledDynamicFeedSnapshot.accountMID, 2002)
        XCTAssertTrue(enabledDynamicFeedSnapshot.cookieHeader.contains("SESSDATA=playback-session"))
    }

    func testSelectingDynamicFeedAccountUsesSecondaryCredentialsAndPersists() throws {
        let keychain = makeKeychain()
        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "dynamic-session", csrf: "dynamic-csrf")
        )

        try store.selectDynamicFeedAccount(mid: 2002)

        let snapshot = store.credentialSnapshot(for: .dynamicFeed, multiAccountEnabled: true)
        XCTAssertEqual(snapshot.accountMID, 2002)
        XCTAssertEqual(snapshot.csrfToken, "dynamic-csrf")
        XCTAssertTrue(snapshot.cookieHeader.contains("SESSDATA=dynamic-session"))

        let identityKey = store.accountCacheIdentityKey(
            for: .dynamicFeed,
            multiAccountEnabled: true
        )
        XCTAssertTrue(identityKey.contains("dynamicFeed"))
        XCTAssertTrue(identityKey.contains("mid-2002"))

        let reloadedStore = SessionStore(keychain: keychain)
        let reloadedSnapshot = reloadedStore.credentialSnapshot(
            for: .dynamicFeed,
            multiAccountEnabled: true
        )
        XCTAssertEqual(reloadedStore.dynamicFeedAccountMID, 2002)
        XCTAssertEqual(reloadedSnapshot.accountMID, 2002)
        XCTAssertEqual(reloadedSnapshot.csrfToken, "dynamic-csrf")
    }

    func testSelectingInteractionAccountUsesSecondaryCredentialsAndPersists() throws {
        let keychain = makeKeychain()
        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "interaction-session", csrf: "interaction-csrf")
        )

        try store.selectInteractionAccount(mid: 2002)

        let snapshot = store.credentialSnapshot(for: .interaction, multiAccountEnabled: true)
        XCTAssertEqual(snapshot.accountMID, 2002)
        XCTAssertEqual(snapshot.csrfToken, "interaction-csrf")
        XCTAssertTrue(snapshot.cookieHeader.contains("SESSDATA=interaction-session"))

        let reloadedStore = SessionStore(keychain: keychain)
        let reloadedSnapshot = reloadedStore.credentialSnapshot(
            for: .interaction,
            multiAccountEnabled: true
        )
        XCTAssertEqual(reloadedStore.interactionAccountMID, 2002)
        XCTAssertEqual(reloadedSnapshot.accountMID, 2002)
        XCTAssertEqual(reloadedSnapshot.csrfToken, "interaction-csrf")
    }

    func testHistoryPolicyCanUsePlaybackAccountOrDisableWrites() throws {
        let store = makeSessionStore()
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "playback-session", csrf: "playback-csrf")
        )
        try store.selectPlaybackAccount(mid: 2002)

        try store.setHistoryAccountPolicy(.disabled)
        let disabledRead = store.credentialSnapshot(for: .historyRead, multiAccountEnabled: true)
        let disabledWrite = store.credentialSnapshot(for: .historyWrite, multiAccountEnabled: true)
        let experimentOffWrite = store.credentialSnapshot(for: .historyWrite, multiAccountEnabled: false)

        XCTAssertEqual(disabledRead.accountMID, 1001)
        XCTAssertTrue(disabledRead.isPurposeEnabled)
        XCTAssertNil(disabledWrite.accountMID)
        XCTAssertFalse(disabledWrite.isPurposeEnabled)
        XCTAssertEqual(experimentOffWrite.accountMID, 1001)
        XCTAssertTrue(experimentOffWrite.isPurposeEnabled)

        try store.setHistoryAccountPolicy(.playback)
        XCTAssertEqual(
            store.credentialSnapshot(for: .historyRead, multiAccountEnabled: true).accountMID,
            2002
        )
        XCTAssertEqual(
            store.credentialSnapshot(for: .historyWrite, multiAccountEnabled: true).accountMID,
            2002
        )
    }

    func testSwitchingMainAccountUpdatesCompatibilityStateAndPersists() throws {
        let keychain = makeKeychain()
        let store = SessionStore(keychain: keychain)
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "second-session", csrf: "second-csrf")
        )
        store.updateAccountUser(
            mid: 2002,
            user: NavUserInfo(
                isLogin: true,
                face: "https://example.com/avatar.jpg",
                uname: "Second Account",
                mid: 2002,
                wbiImg: nil
            )
        )

        try store.selectMainAccount(mid: 2002)

        XCTAssertEqual(store.mainAccountMID, 2002)
        XCTAssertEqual(store.sessdata, "second-session")
        XCTAssertEqual(store.user?.mid, 2002)
        XCTAssertEqual(store.user?.uname, "Second Account")
        XCTAssertEqual(store.csrfToken(), "second-csrf")

        let reloadedStore = SessionStore(keychain: keychain)
        XCTAssertEqual(reloadedStore.mainAccountMID, 2002)
        XCTAssertEqual(reloadedStore.user?.uname, "Second Account")
        XCTAssertTrue(reloadedStore.cookieHeader().contains("SESSDATA=second-session"))
    }

    func testRemovingAssignedSecondaryAccountFallsBackToMain() throws {
        let store = makeSessionStore()
        defer { try? store.logout() }
        try saveMainAccount(mid: 1001, session: "main-session", in: store)
        _ = try store.saveAdditionalAccount(
            cookies(mid: 2002, session: "playback-session", csrf: "playback-csrf")
        )
        try store.selectPlaybackAccount(mid: 2002)
        try store.selectDynamicFeedAccount(mid: 2002)
        try store.selectInteractionAccount(mid: 2002)
        try store.setHistoryAccountPolicy(.playback)

        try store.removeAccount(mid: 2002)

        XCTAssertEqual(store.accounts.map(\.mid), [1001])
        XCTAssertEqual(store.playbackAccountMID, 1001)
        XCTAssertEqual(store.dynamicFeedAccountMID, 1001)
        XCTAssertEqual(store.interactionAccountMID, 1001)
        XCTAssertEqual(
            store.credentialSnapshot(for: .historyRead, multiAccountEnabled: true).accountMID,
            1001
        )
        XCTAssertThrowsError(try store.removeAccount(mid: 1001)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                MultiAccountSessionError.cannotRemoveMainAccount.localizedDescription
            )
        }
    }

    func testAPIConfigurationDoesNotShareAutomaticCookies() {
        let configuration = BiliURLSessionFactory.makeAPIConfiguration()

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }

    func testRemovingHistoryMetadataPreservesPlaybackPayload() throws {
        let data = try JSONDecoder().decode(
            PlayURLData.self,
            from: Data(
                """
                {
                  "quality": 80,
                  "accept_quality": [116, 80],
                  "accept_description": ["1080P 60帧", "1080P"],
                  "last_play_time": 12345,
                  "last_play_cid": 67890
                }
                """.utf8
            )
        )

        let sanitized = data.removingHistoryMetadata()

        XCTAssertEqual(sanitized.quality, 80)
        XCTAssertEqual(sanitized.acceptQuality, [116, 80])
        XCTAssertEqual(sanitized.acceptDescription, ["1080P 60帧", "1080P"])
        XCTAssertNil(sanitized.lastPlayTime)
        XCTAssertNil(sanitized.lastPlayCID)
    }

    private func makeSessionStore() -> SessionStore {
        SessionStore(keychain: makeKeychain())
    }

    private func makeKeychain() -> KeychainStore {
        KeychainStore(service: "cc.bili.tests.multi-account.\(UUID().uuidString)")
    }

    private func saveMainAccount(
        mid: Int,
        session: String,
        in store: SessionStore
    ) throws {
        try store.saveLoginCookies(
            [
                "buvid3": "buvid-\(mid)",
                "DedeUserID": String(mid),
                "SESSDATA": session,
                "bili_jct": "csrf-\(mid)"
            ],
            credentialKind: .web
        )
    }

    private func cookies(
        mid: Int,
        session: String,
        csrf: String
    ) -> [HTTPCookie] {
        [
            cookie(name: "buvid3", value: "buvid-\(mid)"),
            cookie(name: "DedeUserID", value: String(mid)),
            cookie(name: "SESSDATA", value: session),
            cookie(name: "bili_jct", value: csrf)
        ]
    }

    private func cookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(
            properties: [
                .domain: ".bilibili.com",
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE"
            ]
        )!
    }
}

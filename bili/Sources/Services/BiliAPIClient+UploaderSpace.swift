import Foundation

extension BiliAPIClient {
    func fetchSpaceViewerRelation(mid: Int, snapshot: RequestSnapshot) async throws -> UploaderViewerRelation {
        try Task.checkCancellation()
        let current = await MainActor.run { UploaderSpaceRequestIdentity(self.requestSnapshot()) }
        let identity = UploaderSpaceRequestIdentity(snapshot)
        guard mid > 0, identity == current, identity.isLoggedIn, identity.isPurposeEnabled,
              !identity.guestModeEnabled else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<UploaderViewerRelation> = try await get(
            base: baseURL, path: "/x/relation", query: ["fid": String(mid)],
            referer: "https://space.bilibili.com/\(mid)", userAgent: Self.webUserAgent,
            cookieHeader: snapshot.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let relation = response.payload, relation.following != nil else { throw BiliAPIError.missingPayload }
        return relation
    }

    // Use the space's captured main-account credentials, not the interaction account.
    private func validateOwnSpaceRequest(mid: Int, snapshot: RequestSnapshot) async throws {
        try Task.checkCancellation()
        let identity = UploaderSpaceRequestIdentity(snapshot)
        let current = await MainActor.run { UploaderSpaceRequestIdentity(self.requestSnapshot()) }
        guard identity.ownsSpace(mid: mid), identity == current else {
            throw BiliAPIError.api(code: -101, message: "账号已变更，请重新打开个人空间")
        }
    }

    func fetchOwnSpaceFavoritePreview(mid: Int, snapshot: RequestSnapshot) async throws -> UploaderSpaceFavoriteGroup {
        try await validateOwnSpaceRequest(mid: mid, snapshot: snapshot)
        let response: BiliResponse<UploaderSpaceFavoriteList> = try await get(
            base: baseURL, path: "/x/v3/fav/folder/created/list-all",
            query: ["up_mid": String(mid), "type": "2"],
            referer: "https://space.bilibili.com/\(mid)/favlist", userAgent: Self.webUserAgent,
            cookieHeader: snapshot.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let folders = response.payload?.list, folders.allSatisfy({ $0.id > 0 }) else {
            throw BiliAPIError.missingPayload
        }
        return UploaderSpaceFavoriteGroup(folders: folders)
    }

    func fetchOwnSpaceBangumiPreview(mid: Int, snapshot: RequestSnapshot) async throws -> UploaderSpaceVideoGroup {
        let payload = try await fetchOwnSpaceBangumiPage(mid: mid, snapshot: snapshot, page: 1, pageSize: 3)
        return UploaderSpaceVideoGroup(count: payload.total, items: payload.list)
    }

    func fetchOwnSpaceBangumiPage(
        mid: Int, snapshot: RequestSnapshot, page: Int, pageSize: Int = 20
    ) async throws -> UploaderSpaceBangumiList {
        try await validateOwnSpaceRequest(mid: mid, snapshot: snapshot)
        let page = max(page, 1)
        let response: BiliResponse<UploaderSpaceBangumiList> = try await get(
            base: baseURL, path: "/x/space/bangumi/follow/list",
            query: ["vmid": String(mid), "type": "1", "pn": String(page), "ps": String(min(max(pageSize, 1), 30))],
            referer: "https://space.bilibili.com/\(mid)/bangumi", userAgent: Self.webUserAgent,
            cookieHeader: snapshot.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let payload = response.payload,
              payload.list.allSatisfy({ $0.seasonID != nil }),
              page > 1 || !payload.list.isEmpty || (payload.total ?? 0) == 0 else { throw BiliAPIError.missingPayload }
        return payload
    }

    func fetchUploaderSpaceProfileFallback(mid: Int, snapshot: RequestSnapshot) async throws -> UploaderProfile {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        let response: BiliResponse<UploaderProfile> = try await get(
            base: baseURL, path: "/x/web-interface/card", query: ["mid": String(mid), "photo": "false"],
            userAgent: Self.webUserAgent, cookieHeader: snapshot.anonymousCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let profile = response.payload else { throw BiliAPIError.missingPayload }
        return profile
    }

    func fetchUploaderSpaceOverview(mid: Int, snapshot: RequestSnapshot) async throws -> UploaderSpaceOverview {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        let profile = BiliAppSigner.Profile.androidLogin
        var fields = [
            "build": profile.build, "version": profile.appVersion,
            "c_locale": "zh_CN", "s_locale": "zh_CN", "channel": profile.channel,
            "mobi_app": profile.mobiApp, "platform": profile.platform,
            "statistics": profile.statistics, "vmid": String(mid)
        ]
        let usesAccount = snapshot.isLoggedIn && snapshot.isAccountPurposeEnabled && !snapshot.guestModeEnabled
        if usesAccount, let accessKey = snapshot.appAccessKey, !accessKey.isEmpty {
            fields["access_key"] = accessKey
        }
        let cookie = usesAccount ? snapshot.cookieHeader : snapshot.anonymousCookieHeader
        let response: BiliResponse<UploaderSpaceOverview> = try await get(
            base: appURL, path: "/x/v2/space", query: BiliAppSigner.sign(fields, profile: profile),
            referer: "https://space.bilibili.com/\(mid)", userAgent: profile.userAgent,
            cookieHeader: cookie,
            additionalHeaders: Self.uploaderAppHeaders(cookieHeader: cookie, profile: profile),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let overview = response.payload, overview.profile.hasProfileContent else { throw BiliAPIError.missingPayload }
        return overview
    }
}

import Foundation

extension BiliAPIClient {
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

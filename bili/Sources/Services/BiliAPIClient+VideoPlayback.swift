import Foundation
import OSLog

extension BiliAPIClient {
    func fetchPlayURL(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let context = await playbackAPIRequestContext()
        let requestedQuality = preferredQuality ?? context.effectivePreferredVideoQuality ?? qn
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: Self.playURLCachePlatform(
                context.playbackStreamSourcePreference.cachePlatform,
                requestedQuality: requestedQuality
            )
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: context.isLoggedIn,
            userMID: context.currentUserMID,
            guestModeEnabled: context.guestModeEnabled,
            credentialVersion: context.playbackCredentialVersion
        )
        if let cached = await cachedPlayURL(
            for: key,
            scope: scope,
            requiredQuality: requestedQuality
        ) {
            PlayerMetricsLog.logger.info(
                "playURLMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return await applyingConfiguredHistoryAccount(
                to: cached,
                playbackUserMID: context.currentUserMID
            )
        }

        let data = try await fetchPlayURLWithPendingRequest(
            cacheKey: key,
            scope: scope,
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            source: "playURL",
            cachePlatform: context.playbackStreamSourcePreference.cachePlatform,
            isStartup: false
        ) { [self] in
            try await fetchPlayURLUncached(
                bvid: bvid,
                cid: cid,
                qn: qn,
                page: page,
                preferredQuality: preferredQuality
            )
        }
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: context.currentUserMID
        )
    }
}

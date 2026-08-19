import Foundation
import OSLog
import QuartzCore

nonisolated struct LiveDanmakuClientContext: Sendable {
    let uid: Int
    let buvid: String
    let cookieHeader: String
    let headers: [String: String]
}

nonisolated struct InteractionRequestContext: Sendable {
    let cookieHeader: String
    let appAccessKey: String?
    let isLoggedIn: Bool
    let csrfToken: String?
    let currentUserMID: Int?
}

nonisolated struct AccountLibraryRequestContext: Sendable {
    let cookieHeader: String
    let isLoggedIn: Bool
    let currentUserMID: Int?
}

nonisolated struct AccountHistoryCursor: Equatable {
    let max: Int
    let viewAt: Int
}

nonisolated struct AccountVideoEntryPage {
    let entries: [AccountVideoEntry]
    let hasMore: Bool
    let nextHistoryCursor: AccountHistoryCursor?
}

nonisolated struct HomeRecommendRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let appAccessKey: String?
    let identityKey: String
    let isLoggedIn: Bool
    let guestModeEnabled: Bool
    let feedSource: HomeRecommendFeedSourcePreference
}

nonisolated struct PlaybackHistoryRequestContext: Sendable {
    let cookieHeader: String
    let appAccessKey: String?
    let isLoggedIn: Bool
    let csrfToken: String?
    let isAccountPurposeEnabled: Bool
}

nonisolated struct VideoListenPlaylistRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let appAccessKey: String?
    let guestModeEnabled: Bool
}

nonisolated struct BiliAPITransportRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let isLoggedIn: Bool
    let csrfToken: String?
    let guestModeEnabled: Bool
}

nonisolated final class BiliAPIClient {
    let baseURL = URL(string: "https://api.bilibili.com")!
    let appURL = URL(string: "https://app.bilibili.com")!
    private let commentURL = URL(string: "https://comment.bilibili.com")!
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let webUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let session: URLSession
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore
    let homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    let playURLCache: PlayURLCache
    let state = BiliAPIClientState()
    static let uploaderLogger = Logger(subsystem: "cc.bili", category: "Uploader")

    struct TargetQualityUnavailableError: LocalizedError, Sendable {
        let requestedQuality: Int
        let fallbackQuality: Int?
        let fallbackData: PlayURLData?

        init(
            requestedQuality: Int,
            fallbackQuality: Int?,
            fallbackData: PlayURLData? = nil
        ) {
            self.requestedQuality = requestedQuality
            self.fallbackQuality = fallbackQuality
            self.fallbackData = fallbackData
        }

        var playableFallbackData: PlayURLData? {
            guard let fallbackData,
                BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                    fallbackData,
                    requestedQuality: requestedQuality,
                    isAuthoritativeSource: true
                )
            else { return nil }
            return fallbackData
        }

        var errorDescription: String? {
            "目标清晰度 \(requestedQuality) 明确不可用"
        }
    }

    nonisolated static func requiresAutomaticCodecNegotiation(requestedQuality: Int) -> Bool {
        switch requestedQuality {
        case 125, 126, 129:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldContinueCodecFallback(
        for data: PlayURLData,
        requestedQuality: Int,
        requestedCodecFamily: VideoCodecFamily? = nil,
        allowsUnavailableQualityFallback: Bool = false
    ) -> Bool {
        if data.hasPlayableMediaQuality(requestedQuality) {
            guard let requestedCodecFamily else { return false }
            return !hasPlayableDASHMedia(
                in: data,
                quality: requestedQuality,
                codecFamily: requestedCodecFamily
            )
        }
        guard allowsUnavailableQualityFallback,
            let requestedCodecFamily,
            data.hasExplicitlyUnavailableQuality(requestedQuality),
            let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                $0 < requestedQuality && data.advertisedQualities.contains($0)
            })
        else { return true }
        return !hasPlayableDASHMedia(
            in: data,
            quality: fallbackQuality,
            codecFamily: requestedCodecFamily
        )
    }

    private nonisolated static func hasPlayableDASHMedia(
        in data: PlayURLData,
        quality: Int,
        codecFamily: VideoCodecFamily
    ) -> Bool {
        guard data.dash?.bestAudioStream?.playURL(cdnPreference: .automatic) != nil else {
            return false
        }
        return (data.dash?.video ?? []).contains { stream in
            guard stream.id == quality,
                stream.videoCodecFamily == codecFamily,
                stream.isHardwareDecodingCompatibleVideo,
                stream.playURL(cdnPreference: .automatic) != nil
            else { return false }
            guard [116, 74].contains(quality) else { return true }
            return DASHStream.numericFrameRate(from: stream.frameRate).map { $0 >= 50 } ?? false
        }
    }

    nonisolated static func startupCandidateQuality(
        in data: PlayURLData,
        requestedQuality: Int
    ) -> Int? {
        data.playVariants
            .filter { variant in
                guard variant.isPlayable, variant.quality <= requestedQuality else {
                    return false
                }
                return variant.quality < requestedQuality
                    || variant.satisfiesPreferredQuality(requestedQuality)
            }
            .map(\.quality)
            .max()
    }

    nonisolated static func nextLowerVideoQuality(after quality: Int) -> Int? {
        BiliVideoQuality.supportedQualities.first { $0 < quality }
    }

    nonisolated static func uploaderDynamicCookieHeader(
        isLoggedIn: Bool,
        authenticatedCookieHeader: String,
        anonymousCookieHeader: String
    ) -> String {
        isLoggedIn ? authenticatedCookieHeader : anonymousCookieHeader
    }

    private struct RequestSnapshot: Sendable {
        let cookieHeader: String
        let anonymousCookieHeader: String
        let appAccessKey: String?
        let homeRecommendIdentityKey: String
        let isLoggedIn: Bool
        let csrfToken: String?
        let currentUserMID: Int?
        let preferredVideoQuality: Int?
        let cellularPreferredVideoQuality: Int?
        let playbackStreamSourcePreference: PlaybackStreamSourcePreference
        let homeRecommendFeedSourcePreference: HomeRecommendFeedSourcePreference
        let guestModeEnabled: Bool
        let playbackCredentialVersion: Int
        let isAccountPurposeEnabled: Bool

        var effectivePreferredVideoQuality: Int? {
            LibraryStore.effectivePreferredVideoQuality(
                preferred: preferredVideoQuality,
                cellular: cellularPreferredVideoQuality,
                networkClass: PlaybackEnvironment.current.networkClass
            )
        }
    }

    init(
        session: URLSession = .shared,
        sessionStore: SessionStore,
        libraryStore: LibraryStore,
        homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore,
        playURLCache: PlayURLCache = .shared
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.homeRecommendDiagnosticsStore = homeRecommendDiagnosticsStore
        self.playURLCache = playURLCache
    }

    @MainActor
    private func requestSnapshot(
        purpose: BiliAccountPurpose = .main
    ) -> RequestSnapshot {
        let account = sessionStore.credentialSnapshot(
            for: purpose,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        return RequestSnapshot(
            cookieHeader: account.cookieHeader,
            anonymousCookieHeader: account.anonymousCookieHeader,
            appAccessKey: account.accessKey,
            homeRecommendIdentityKey: sessionStore.recommendCacheIdentityKey(
                guestModeEnabled: libraryStore.guestModeEnabled
            ),
            isLoggedIn: account.isLoggedIn,
            csrfToken: account.csrfToken,
            currentUserMID: account.accountMID,
            preferredVideoQuality: libraryStore.preferredVideoQuality,
            cellularPreferredVideoQuality: libraryStore.cellularPreferredVideoQuality,
            playbackStreamSourcePreference: libraryStore.playbackStreamSourcePreference,
            homeRecommendFeedSourcePreference: libraryStore.homeRecommendFeedSourcePreference,
            guestModeEnabled: libraryStore.guestModeEnabled,
            playbackCredentialVersion: account.version,
            isAccountPurposeEnabled: account.isPurposeEnabled
        )
    }

    func transportRequestContext(
        purpose: BiliAccountPurpose = .main
    ) async -> BiliAPITransportRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return BiliAPITransportRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            guestModeEnabled: snapshot.guestModeEnabled
        )
    }

    func transportSession() -> URLSession {
        session
    }

    func playbackHistoryRequestContext() async -> PlaybackHistoryRequestContext {
        let snapshot = await requestSnapshot(purpose: .historyWrite)
        return PlaybackHistoryRequestContext(
            cookieHeader: snapshot.cookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            isAccountPurposeEnabled: snapshot.isAccountPurposeEnabled
        )
    }

    func videoListenPlaylistRequestContext() async -> VideoListenPlaylistRequestContext {
        let snapshot = await requestSnapshot(purpose: .playback)
        return VideoListenPlaylistRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            guestModeEnabled: snapshot.guestModeEnabled
        )
    }

    func interactionRequestContext(
        purpose: BiliAccountPurpose = .interaction
    ) async -> InteractionRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return InteractionRequestContext(
            cookieHeader: snapshot.cookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn,
            csrfToken: snapshot.csrfToken,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func playbackAPIRequestContext() async -> PlaybackAPIRequestContext {
        let snapshot = await requestSnapshot(purpose: .playback)
        return PlaybackAPIRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            effectivePreferredVideoQuality: snapshot.effectivePreferredVideoQuality,
            playbackStreamSourcePreference: snapshot.playbackStreamSourcePreference,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled,
            playbackCredentialVersion: snapshot.playbackCredentialVersion,
            isAccountPurposeEnabled: snapshot.isAccountPurposeEnabled
        )
    }

    func videoContentRequestContext() async -> VideoContentRequestContext {
        let snapshot = await requestSnapshot()
        return VideoContentRequestContext(
            cookieHeader: snapshot.cookieHeader,
            guestModeCookieHeader: snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil,
            credentialVersion: snapshot.playbackCredentialVersion
        )
    }

    func danmakuRequestContext() async -> DanmakuRequestContext {
        let snapshot = await requestSnapshot()
        return DanmakuRequestContext(
            commentURL: commentURL,
            apiURL: baseURL,
            guestModeCookieHeader: snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil
        )
    }

    func homeRecommendRequestContext() async -> HomeRecommendRequestContext {
        let snapshot = await requestSnapshot()
        return HomeRecommendRequestContext(
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            identityKey: snapshot.homeRecommendIdentityKey,
            isLoggedIn: snapshot.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled,
            feedSource: snapshot.homeRecommendFeedSourcePreference
        )
    }

    func homeRecommendTask(for key: String) async -> Task<[VideoItem], Error>? {
        await state.videoListTask(for: key)
    }

    func setHomeRecommendTask(_ task: Task<[VideoItem], Error>, for key: String) async {
        await state.setVideoListTask(task, for: key)
    }

    func clearHomeRecommendTask(for key: String) async {
        await state.clearVideoListTask(for: key)
    }

    func clearHomeRecommendState() async {
        await state.clearHomeRecommendState()
    }

    func homeRecommendAppFeedIndex(defaulting defaultIndex: Int) async -> Int {
        await state.appRecommendFeedIndex(defaulting: defaultIndex)
    }

    func setHomeRecommendAppFeedIndex(_ index: Int?) async {
        await state.setAppRecommendFeedIndex(index)
    }

    func homeRecommendGuestModeCookieHeader() async -> String? {
        let context = await transportRequestContext()
        return context.guestModeEnabled ? context.anonymousCookieHeader : nil
    }

    func fetchDanmakuData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, priority: .utility)
    }

    func videoContentListTask(for key: String) async -> Task<[VideoItem], Error>? {
        await state.videoListTask(for: key)
    }

    func setVideoContentListTask(_ task: Task<[VideoItem], Error>, for key: String) async {
        await state.setVideoListTask(task, for: key)
    }

    func clearVideoContentListTask(for key: String) async {
        await state.clearVideoListTask(for: key)
    }

    func videoContentDetailTask(for key: String) async -> Task<VideoItem, Error>? {
        await state.videoDetailTask(for: key)
    }

    func setVideoContentDetailTask(_ task: Task<VideoItem, Error>, for key: String) async {
        await state.setVideoDetailTask(task, for: key)
    }

    func clearVideoContentDetailTask(for key: String) async {
        await state.clearVideoDetailTask(for: key)
    }

    func accountLibraryRequestContext(
        purpose: BiliAccountPurpose
    ) async -> AccountLibraryRequestContext {
        let snapshot = await requestSnapshot(purpose: purpose)
        return AccountLibraryRequestContext(
            cookieHeader: snapshot.cookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func liveAccountRequestIdentity() async -> (cookieHeader: String, currentUserMID: Int?) {
        let snapshot = await requestSnapshot()
        return (snapshot.cookieHeader, snapshot.currentUserMID)
    }

    func liveDanmakuTransportData(
        for request: URLRequest,
        transportSession: URLSession?
    ) async throws -> Data {
        if let transportSession {
            return try await transportSession.data(for: request).0
        }
        return try await session.data(for: request).0
    }

    func dynamicFeedRequestContext() async -> (
        cookieHeader: String,
        anonymousCookieHeader: String,
        isLoggedIn: Bool,
        currentUserMID: Int?
    ) {
        let snapshot = await requestSnapshot(purpose: .dynamicFeed)
        return (
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            isLoggedIn: snapshot.isLoggedIn,
            currentUserMID: snapshot.currentUserMID
        )
    }

    func clearWBIKeysForDynamicFeed() async {
        await state.clearWBIKeys()
    }

    func anonymousCookieHeader(
        purpose: BiliAccountPurpose = .main
    ) async -> String {
        let snapshot = await requestSnapshot(purpose: purpose)
        return snapshot.anonymousCookieHeader
    }

    func uploaderProfileRequestContext() async -> (
        cookieHeader: String,
        anonymousCookieHeader: String,
        appAccessKey: String?,
        isLoggedIn: Bool
    ) {
        let snapshot = await requestSnapshot()
        return (
            cookieHeader: snapshot.cookieHeader,
            anonymousCookieHeader: snapshot.anonymousCookieHeader,
            appAccessKey: snapshot.appAccessKey,
            isLoggedIn: snapshot.isLoggedIn
        )
    }

    func uploaderProfileTask(for mid: Int) async -> Task<UploaderProfile, Error>? {
        await state.uploaderProfileTask(for: mid)
    }

    func setUploaderProfileTask(_ task: Task<UploaderProfile, Error>, for mid: Int) async {
        await state.setUploaderProfileTask(task, for: mid)
    }

    func clearUploaderProfileTask(for mid: Int) async {
        await state.clearUploaderProfileTask(for: mid)
    }

    private func preferredVideoQuality() async -> Int? {
        let snapshot = await requestSnapshot()
        return snapshot.effectivePreferredVideoQuality
    }

    private func playbackStreamSourcePreference() async -> PlaybackStreamSourcePreference {
        let snapshot = await requestSnapshot()
        return snapshot.playbackStreamSourcePreference
    }

    private func isLoggedIn() async -> Bool {
        let snapshot = await requestSnapshot()
        return snapshot.isLoggedIn
    }

    func prewarmStartupResources() async {
        async let keys: Void = prewarmPlaybackSigningKeys()
        async let nav: NavUserInfo? = try? fetchNavUser()
        _ = await (keys, nav)
    }

    func resetPlaybackAuthorizationState() async {
        await state.clearAllPlayURLFailuresAndTasks()
        await ResourceCacheCenter.clearAPI()
    }

    func activeNavUserTask() async -> Task<NavUserInfo, Error>? {
        await state.navUserTask()
    }

    func storeNavUserTask(_ task: Task<NavUserInfo, Error>) async {
        await state.setNavUserTask(task)
    }

    func clearStoredNavUserTask() async {
        await state.clearNavUserTask()
    }

    func applyingConfiguredHistoryAccount(
        to data: PlayURLData,
        playbackUserMID: Int?
    ) async -> PlayURLData {
        let historySnapshot = await requestSnapshot(purpose: .historyRead)
        guard historySnapshot.currentUserMID == playbackUserMID else {
            return data.removingHistoryMetadata()
        }
        return data
    }

    func fetchPlayURLUncached(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let requestStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot(purpose: .playback)
        let anonymousCookieHeader = snapshot.anonymousCookieHeader
        let playCookieHeader = snapshot.cookieHeader
        let requestedQuality =
            preferredQuality
            ?? snapshot.effectivePreferredVideoQuality
            ?? qn
        let streamSource = snapshot.playbackStreamSourcePreference
        let initialCodecPreference =
            PlayURLCodecPreference.primaryPlaybackOrder(
                requestedQuality: requestedQuality
            ).first ?? .hevc
        let query = Self.playURLQuery(
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            streamSource: streamSource,
            codecPreference: initialCodecPreference
        )
        var lastError: Error?
        var bestPlayableData: PlayURLData?

        logPlayURLStage("start", bvid: bvid, cid: cid, start: requestStart)

        let wbiStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "wbiPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-wbi-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: wbiStageStart
            ) { [self] in
                let keys = try await fetchWBIKeys(priority: .userInitiated)
                return try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    referer: referer,
                    cookieHeader: playCookieHeader,
                    stagePrefix: "wbiPrimary",
                    cookieModePrefix: "auth-wbi-\(streamSource.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    streamSource: streamSource,
                    priority: .userInitiated
                )
            }
            logPlayURLStage("wbiPrimary", bvid: bvid, cid: cid, start: wbiStageStart, data: playable)
            if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                logPlayURLStage("completeWBIPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            logPreferredQualityMiss(
                stage: "wbiPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
            bestPlayableData = playable
        } catch {
            lastError = error
        }

        // The mobile request profile can be handed a low AV1 rendition even when
        // the web player exposes the configured quality. Verify only a miss via
        // the web WBI profile before accepting a lower-quality fallback.
        if streamSource != .web {
            let webQualityProbeStart = CACurrentMediaTime()
            do {
                let playable = try await runCachedPlayURLStage(
                    "wbiWebQualityProbe",
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    cookieMode: "auth-wbi-webQualityProbe-\(PlaybackStreamSourcePreference.web.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    start: webQualityProbeStart
                ) { [self] in
                    let keys = try await fetchWBIKeys(priority: .userInitiated)
                    return try await fetchWBIPlayURLWithCodecFallbacks(
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality,
                        keys: keys,
                        referer: referer,
                        cookieHeader: playCookieHeader,
                        stagePrefix: "wbiWebQualityProbe",
                        cookieModePrefix:
                            "auth-wbi-webQualityProbe-\(PlaybackStreamSourcePreference.web.cachePlatform)",
                        credentialVersion: snapshot.playbackCredentialVersion,
                        streamSource: .web,
                        priority: .userInitiated
                    )
                }
                logPlayURLStage("wbiWebQualityProbe", bvid: bvid, cid: cid, start: webQualityProbeStart, data: playable)
                if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                    logPlayURLStage(
                        "completeWBIWebQualityProbe", bvid: bvid, cid: cid, start: requestStart, data: playable)
                    return playable
                }
                logPreferredQualityMiss(
                    stage: "wbiWebQualityProbe", bvid: bvid, cid: cid, requestedQuality: requestedQuality,
                    data: playable)
                bestPlayableData = preferredPlayURLCandidate(
                    bestPlayableData,
                    playable,
                    requestedQuality: requestedQuality
                )
            } catch {
                lastError = error
            }
        }

        let legacyStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "legacyPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-legacy-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: legacyStageStart
            ) { [self] in
                try await fetchLegacyPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    referer: referer,
                    cookieHeader: playCookieHeader,
                    streamSource: streamSource,
                    priority: .userInitiated
                )
            }
            logPlayURLStage("legacyPrimary", bvid: bvid, cid: cid, start: legacyStageStart, data: playable)
            if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                logPlayURLStage("completeLegacyPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            logPreferredQualityMiss(
                stage: "legacyPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
            bestPlayableData = preferredPlayURLCandidate(bestPlayableData, playable, requestedQuality: requestedQuality)
        } catch {
            lastError = error
        }

        let metadataStageStart = CACurrentMediaTime()
        do {
            let metadata = try await runCachedPlayURLStage(
                "anonymousMetadata",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-metadata-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: metadataStageStart
            ) { [self] in
                try await fetchAnonymousPlayURLMetadata(
                    bvid: bvid,
                    cid: cid,
                    referer: referer,
                    query: query,
                    streamSource: streamSource
                )
            }
            logPlayURLStage("anonymousMetadata", bvid: bvid, cid: cid, start: metadataStageStart, data: metadata)
            if !metadata.playVariants.isEmpty {
                let merged = bestPlayableData?.mergingPlayableStreams(from: metadata) ?? metadata
                if merged.highestPlayableQuality >= (bestPlayableData?.highestPlayableQuality ?? 0) {
                    bestPlayableData = merged
                }
            }
        } catch {
            lastError = error
        }

        let legacyAnonymousStageStart = CACurrentMediaTime()
        do {
            let playableFallback = try await runCachedPlayURLStage(
                "legacyAnonymousFallback",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-legacy-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: legacyAnonymousStageStart
            ) { [self] in
                try await fetchLegacyPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    streamSource: streamSource,
                    priority: .userInitiated
                )
            }
            logPlayURLStage(
                "legacyAnonymousFallback", bvid: bvid, cid: cid, start: legacyAnonymousStageStart,
                data: playableFallback)
            if let existing = bestPlayableData {
                let merged = existing.mergingPlayableStreams(from: playableFallback)
                if merged.highestPlayableQuality > existing.highestPlayableQuality
                    || playableFallback.durl?.isEmpty == false
                {
                    bestPlayableData = merged
                }
            } else if playableFallback.highestPlayableQuality > 0 {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        let webpageStageStart = CACurrentMediaTime()
        do {
            let webpagePlayable = try await runCachedPlayURLStage(
                "webpagePlayInfo",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: webpageStageStart
            ) { [self] in
                try await fetchWebPagePlayInfo(
                    bvid: bvid,
                    page: page,
                    referer: referer,
                    cookieHeader: playCookieHeader
                )
            }
            logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, data: webpagePlayable)
            if let bestPlayableData {
                let merged = bestPlayableData.mergingPlayableStreams(from: webpagePlayable)
                logPlayURLStage("completeWebpageMerged", bvid: bvid, cid: cid, start: requestStart, data: merged)
                return merged
            }
            logPlayURLStage("completeWebpage", bvid: bvid, cid: cid, start: requestStart, data: webpagePlayable)
            return webpagePlayable
        } catch {
            if let bestPlayableData {
                logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, error: error)
                logPlayURLStage(
                    "completeBestFallback", bvid: bvid, cid: cid, start: requestStart, data: bestPlayableData)
                return bestPlayableData
            }
            logPlayURLStage("completeFailed", bvid: bvid, cid: cid, start: requestStart, error: lastError ?? error)
            throw lastError ?? error
        }
    }

    func fetchWebPagePlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot(purpose: .playback)
        let requestedQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let data = try await runCachedPlayURLStage(
            "webpagePlayInfo",
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
            credentialVersion: snapshot.playbackCredentialVersion,
            start: stageStart
        ) { [self] in
            try await fetchWebPagePlayInfo(
                bvid: bvid,
                page: page,
                referer: referer,
                cookieHeader: snapshot.cookieHeader
            )
        }
        logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: stageStart, data: data)
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: snapshot.currentUserMID
        )
    }

    func makePiliPlusWebpageHedge(
        bvid: String,
        page: Int?,
        delayNanoseconds: UInt64
    ) -> PiliPlusWebpageHedge {
        let scheduledAt = CACurrentMediaTime()
        let delayMilliseconds = Double(delayNanoseconds) / 1_000_000
        let task = Task<PlayURLData, Error>(priority: .userInitiated) { [self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageHedgeDiagnosticMessage(
                            event: "webpageHedgeCancelled",
                            delayMilliseconds: delayMilliseconds,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt),
                            phase: "beforeStart"
                        ),
                        bvid: bvid
                    )
                    throw error
                }
            }

            let requestStart = CACurrentMediaTime()
            await recordStartupSchedulerMessage(
                Self.piliPlusWebpageHedgeDiagnosticMessage(
                    event: "webpageHedgeStart",
                    delayMilliseconds: delayMilliseconds,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt)
                ),
                bvid: bvid
            )
            do {
                try Task.checkCancellation()
                let data = try await fetchPiliPlusUncachedWebPagePlayURL(
                    bvid: bvid,
                    page: page
                )
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageHedgeDiagnosticMessage(
                        event: "webpageHedgeReady",
                        delayMilliseconds: delayMilliseconds,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt)
                    ),
                    bvid: bvid
                )
                return data
            } catch {
                let isCancellation =
                    Task.isCancelled
                    || error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageHedgeDiagnosticMessage(
                        event: isCancellation ? "webpageHedgeCancelled" : "webpageHedgeFailed",
                        delayMilliseconds: delayMilliseconds,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt),
                        phase: isCancellation ? "inFlight" : "request",
                        requestElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart)
                    ),
                    bvid: bvid
                )
                throw error
            }
        }
        return PiliPlusWebpageHedge(
            scheduledAt: scheduledAt,
            delayNanoseconds: delayNanoseconds,
            task: task
        )
    }

    private func fetchPiliPlusUncachedWebPagePlayURL(
        bvid: String,
        page: Int?
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot(purpose: .playback)
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let data = try await fetchWebPagePlayInfo(
            bvid: bvid,
            page: page,
            referer: referer,
            cookieHeader: snapshot.cookieHeader
        )
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: snapshot.currentUserMID
        )
    }

    func fetchPiliPlusStyleStartupFallbackPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        webpageHedge: PiliPlusWebpageHedge? = nil
    ) async throws -> PlayURLData {
        _ = cid
        let webpageHedge =
            webpageHedge
            ?? makePiliPlusWebpageHedge(
                bvid: bvid,
                page: page,
                delayNanoseconds: 0
            )
        let webpageStart = webpageHedge.scheduledAt
        let webpageTask = webpageHedge.task
        defer { webpageTask.cancel() }
        do {
            let webpageData = try await Self.awaitSharedTask(webpageTask)
            await recordStartupSchedulerMessage(
                Self.piliPlusWebpageHedgeDiagnosticMessage(
                    event: "webpageHedgeWon",
                    delayMilliseconds: Double(webpageHedge.delayNanoseconds) / 1_000_000,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart)
                ),
                bvid: bvid
            )
            await recordStartupSchedulerMessage(
                Self.piliPlusStartupFallbackDiagnosticMessage(
                    result: "success",
                    route: "webpage",
                    requestedQuality: requestedQuality,
                    selectedQuality: Self.startupCandidateQuality(
                        in: webpageData,
                        requestedQuality: requestedQuality
                    ),
                    legacyResult: "skipped",
                    legacyElapsedMilliseconds: nil,
                    standardWBIResult: "notStarted",
                    standardWBIQuality: nil,
                    standardWBIElapsedMilliseconds: nil,
                    webpageElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart)
                ),
                bvid: bvid
            )
            return webpageData
        } catch {
            guard !Task.isCancelled else { throw error }
            await recordStartupSchedulerMessage(
                Self.piliPlusStartupFallbackDiagnosticMessage(
                    result: "failure",
                    route: "webpage",
                    requestedQuality: requestedQuality,
                    selectedQuality: nil,
                    legacyResult: "skipped",
                    legacyElapsedMilliseconds: nil,
                    standardWBIResult: "notStarted",
                    standardWBIQuality: nil,
                    standardWBIElapsedMilliseconds: nil,
                    webpageElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    webpageError: error
                ),
                bvid: bvid
            )
            throw error
        }
    }

    func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        requestLease: StartupPlayURLRequestLease? = nil,
        requestSource: StartupPlayURLRequestSource = .preload
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot(purpose: .playback)
        let configuredQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality
        let requestedQuality = startupRequestedQuality(configuredQuality: configuredQuality)
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: Self.playURLCachePlatform(
                snapshot.playbackStreamSourcePreference.cachePlatform,
                requestedQuality: requestedQuality,
                isStartup: true
            )
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled,
            credentialVersion: snapshot.playbackCredentialVersion
        )
        let allowsVerifiedLowerQualityFallback = PiliPlusStylePlayURLSelectionExperiment.stored()
        if let cached = await playURLCache.value(
            for: key,
            scope: scope,
            requiredQuality: requestedQuality,
            allowsVerifiedLowerQualityFallback: allowsVerifiedLowerQualityFallback
        ) {
            PlayerMetricsLog.logger.info(
                "playURLStartupMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return await applyingConfiguredHistoryAccount(
                to: cached,
                playbackUserMID: snapshot.currentUserMID
            )
        }

        let data = try await fetchPlayURLWithPendingRequest(
            cacheKey: key,
            scope: scope,
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            source: "startup",
            cachePlatform: snapshot.playbackStreamSourcePreference.cachePlatform,
            isStartup: true
        ) { [self] in
            try await fetchStartupPlayURLUncached(
                bvid: bvid,
                cid: cid,
                page: page,
                preferredQuality: preferredQuality,
                requestLease: requestLease,
                requestSource: requestSource
            )
        }
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: snapshot.currentUserMID
        )
    }

    nonisolated static func awaitSharedTask<Value: Sendable>(
        _ task: Task<Value, Error>
    ) async throws -> Value {
        let waiter = PendingTaskWaiter<Value>()
        Task(priority: .utility) {
            do {
                waiter.succeed(try await task.value)
            } catch {
                waiter.fail(error)
            }
        }
        return try await withTaskCancellationHandler {
            try await waiter.value()
        } onCancel: {
            waiter.fail(CancellationError())
        }
    }

    private func fetchStartupPlayURLUncached(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        requestLease: StartupPlayURLRequestLease?,
        requestSource: StartupPlayURLRequestSource
    ) async throws -> PlayURLData {
        let storedPreferredQuality = await preferredVideoQuality()
        let configuredQuality = preferredQuality ?? storedPreferredQuality
        let requestedQuality = startupRequestedQuality(configuredQuality: configuredQuality)
        let requestStart = CACurrentMediaTime()
        var bestStartupData: PlayURLData?

        let racedStartupResult = try await fetchRacedStartupPlayURL(
            bvid: bvid,
            cid: cid,
            page: page,
            requestedQuality: requestedQuality,
            requestLease: requestLease,
            requestSource: requestSource
        )

        if let racedStartupResult {
            let racedStartupData = racedStartupResult.data
            if racedStartupData.hasPlayableMediaQuality(requestedQuality) {
                return racedStartupData
            }
            if racedStartupResult.isVerifiedUnavailablePreferredFallback {
                return racedStartupData
            }
            bestStartupData = preferredStartupCandidate(
                bestStartupData,
                racedStartupData,
                requestedQuality: requestedQuality
            )
        }

        do {
            let data = try await fetchPlayURLUncached(
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                page: page,
                preferredQuality: requestedQuality
            )
            if data.hasPlayableMediaQuality(requestedQuality) {
                return data
            }
            bestStartupData = preferredStartupCandidate(
                bestStartupData,
                data,
                requestedQuality: requestedQuality
            )
            logPreferredQualityMiss(
                stage: "startupFullFallback",
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                data: data
            )
        } catch {
            guard !Task.isCancelled else { throw error }
            logPlayURLStage(
                "startupFullFallback",
                bvid: bvid,
                cid: cid,
                start: requestStart,
                error: error
            )
        }

        guard let bestStartupData else { throw BiliAPIError.emptyPlayURL }
        return bestStartupData
    }

    nonisolated static func piliPlusWebpageHedgeDiagnosticMessage(
        event: String,
        delayMilliseconds: Double,
        elapsedMilliseconds: Double,
        phase: String? = nil,
        requestElapsedMilliseconds: Double? = nil
    ) -> String {
        var parts = [
            "piliPlusWebpageHedge",
            "event=\(event)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "delay=\(Int(delayMilliseconds.rounded()))ms",
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms",
        ]
        if let phase {
            parts.append("phase=\(phase)")
        }
        if let requestElapsedMilliseconds {
            parts.append("request=\(Int(requestElapsedMilliseconds.rounded()))ms")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusWebpageStreamDiagnosticMessage(
        mode: String,
        receivedBytes: Int,
        expectedBytes: Int64?,
        elapsedMilliseconds: Double,
        fallbackReason: String? = nil
    ) -> String {
        var parts = [
            "piliPlusWebpageStream",
            "mode=\(mode)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "received=\(receivedBytes)",
            "expected=\(expectedBytes.map(String.init) ?? "-")",
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms",
        ]
        if let expectedBytes, expectedBytes > Int64(receivedBytes) {
            parts.append("saved=\(expectedBytes - Int64(receivedBytes))")
        }
        if let fallbackReason {
            parts.append("fallbackReason=\(fallbackReason)")
        }
        return parts.joined(separator: " ")
    }

    private nonisolated func startupRequestedQuality(configuredQuality: Int?) -> Int {
        configuredQuality ?? LibraryStore.defaultPreferredVideoQuality
    }

    nonisolated static func startupWBIHealthFailureReason(for error: Error) -> String? {
        guard !(error is CancellationError),
            (error as? URLError)?.code != .cancelled
        else { return nil }
        guard !(error is TargetQualityUnavailableError) else { return nil }
        if let urlError = error as? URLError {
            return "network.\(urlError.code.rawValue)"
        }
        guard let apiError = error as? BiliAPIError else { return "unknown" }
        switch apiError {
        case .unsupportedHardwarePlayback:
            return nil
        case .emptyPlayURL:
            return nil
        case .invalidURL:
            return "invalidURL"
        case .emptyData:
            return "emptyData"
        case .api(let code, _):
            return "api.\(code)"
        case .missingPayload:
            return "missingPayload"
        case .missingSESSDATA:
            return "missingSESSDATA"
        case .missingCSRF:
            return "missingCSRF"
        }
    }

    private func cancelPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String
    ) async {
        let snapshot = await requestSnapshot(purpose: .playback)
        let cacheKey = Self.playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode,
            credentialVersion: snapshot.playbackCredentialVersion
        )
        await state.cancelPlayURLStage(cacheKey)
    }

    private nonisolated func shouldAcceptPlayURLData(_ data: PlayURLData, requestedQuality: Int) -> Bool {
        data.hasPlayableMediaQuality(requestedQuality)
    }

    nonisolated static func canUseUnavailablePreferredStartupFallback(
        _ data: PlayURLData,
        requestedQuality: Int,
        isAuthoritativeSource: Bool
    ) -> Bool {
        guard isAuthoritativeSource,
            data.hasPlayableStreamPayload,
            !data.shouldRefetchForPreferredQuality(requestedQuality)
        else {
            return false
        }

        // Prefer the server's explicit quality ladder. Without one, keep the
        // conservative adjacent-rung check because q116 responses can omit q112.
        if data.hasExplicitlyUnavailableQuality(requestedQuality) {
            guard
                let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                    $0 < requestedQuality && data.advertisedQualities.contains($0)
                })
            else {
                return false
            }
            return data.hasPlayableMediaQuality(fallbackQuality)
        }

        guard let fallbackQuality = nextLowerVideoQuality(after: requestedQuality) else { return true }
        return data.hasPlayableMediaQuality(fallbackQuality)
    }

    nonisolated static func canUsePiliPlusCompatibilityResponse(
        _ data: PlayURLData,
        requestedQuality: Int
    ) -> Bool {
        data.hasPlayableMediaQuality(requestedQuality)
            || canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: requestedQuality,
                isAuthoritativeSource: true
            )
    }

    private nonisolated func preferredPlayURLCandidate(
        _ lhs: PlayURLData?,
        _ rhs: PlayURLData,
        requestedQuality: Int
    ) -> PlayURLData {
        guard let lhs else { return rhs }
        let lhsMatches = shouldAcceptPlayURLData(lhs, requestedQuality: requestedQuality)
        let rhsMatches = shouldAcceptPlayURLData(rhs, requestedQuality: requestedQuality)
        if lhsMatches != rhsMatches {
            return rhsMatches ? rhs : lhs
        }
        let lhsQuality = Self.startupCandidateQuality(in: lhs, requestedQuality: requestedQuality)
        let rhsQuality = Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality)
        guard let rhsQuality else { return lhs }
        guard let lhsQuality else { return rhs }
        return rhsQuality > lhsQuality ? rhs : lhs
    }

    func logPreferredQualityMiss(
        stage: String,
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        data: PlayURLData
    ) {
        PlayerMetricsLog.logger.info(
            "preferredQualityMiss stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) requested=\(requestedQuality, privacy: .public) available=\(self.qualitySummary(data.playVariants), privacy: .public)"
        )
    }

    func fetchWBIStartupPlayURL(
        bvid: String,
        cid: Int,
        keys: WBIKeys,
        preferredQuality: Int?
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = await requestSnapshot(purpose: .playback)
        let requestedQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let authCookieHeader = snapshot.cookieHeader
        let anonymousCookieHeader = snapshot.anonymousCookieHeader
        var lastError: Error?
        do {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: keys,
                referer: referer,
                cookieHeader: authCookieHeader,
                stagePrefix: "startupWBI",
                cookieModePrefix: "auth-wbi-cached-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder(
                    requestedQuality: requestedQuality
                )
            )
            logPlayURLStage("startupWBI", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        } catch {
            lastError = error
        }

        if let error = lastError,
            shouldRetryWBIAnonymously(after: error)
        {
            do {
                let data = try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    stagePrefix: "startupWBIAnonymous",
                    cookieModePrefix: "anon-wbi-cached-\(streamSource.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    streamSource: streamSource,
                    priority: .userInitiated,
                    codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder(
                        requestedQuality: requestedQuality
                    )
                )
                logPlayURLStage("startupWBIAnonymous", bvid: bvid, cid: cid, start: stageStart, data: data)
                return data
            } catch {
                lastError = error
            }
        }

        guard let error = lastError, shouldRefreshWBIKeys(after: error) else {
            throw lastError ?? BiliAPIError.emptyPlayURL
        }

        let refreshedKeys = try await refreshPlaybackSigningKeys()
        do {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: refreshedKeys,
                referer: referer,
                cookieHeader: authCookieHeader,
                stagePrefix: "startupWBIRefreshed",
                cookieModePrefix: "auth-wbi-refreshed-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder(
                    requestedQuality: requestedQuality
                )
            )
            logPlayURLStage("startupWBIRefreshed", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        } catch {
            lastError = error
        }

        if let error = lastError,
            shouldRetryWBIAnonymously(after: error)
        {
            do {
                let data = try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: refreshedKeys,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    stagePrefix: "startupWBIRefreshedAnonymous",
                    cookieModePrefix: "anon-wbi-refreshed-\(streamSource.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    streamSource: streamSource,
                    priority: .userInitiated,
                    codecPreferences: PlayURLCodecPreference.primaryPlaybackOrder(
                        requestedQuality: requestedQuality
                    )
                )
                logPlayURLStage("startupWBIRefreshedAnonymous", bvid: bvid, cid: cid, start: stageStart, data: data)
                return data
            } catch {
                lastError = error
            }
        }

        if let error = lastError,
            shouldTryExtendedPlayURLCodecFallback(after: error)
        {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: refreshedKeys,
                referer: referer,
                cookieHeader: anonymousCookieHeader.isEmpty ? authCookieHeader : anonymousCookieHeader,
                stagePrefix: "startupWBIExtended",
                cookieModePrefix:
                    "\(anonymousCookieHeader.isEmpty ? "auth-wbi-extended" : "anon-wbi-extended")-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                streamSource: streamSource,
                priority: .userInitiated,
                codecPreferences: PlayURLCodecPreference.extendedPlaybackOrder(
                    requestedQuality: requestedQuality
                )
            )
            logPlayURLStage("startupWBIExtended", bvid: bvid, cid: cid, start: stageStart, data: data)
            return data
        }

        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    func startupWBISuppressionStatus() async -> StartupWBISuppressionStatus? {
        await state.startupWBISuppressionStatus()
    }

    private nonisolated func unavailablePreferredQualityCacheKey(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        snapshot: RequestSnapshot
    ) -> String {
        let networkToken: String
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            networkToken = "wifi"
        case .cellular:
            networkToken = "cellular"
        case .constrained:
            networkToken = "constrained"
        case .unknown:
            networkToken = "unknown"
        }
        let hardwareToken = PlaybackHardwareDecodePolicy.stored() ? "hardware" : "software"
        let codecToken = Self.playURLCodecCachePolicyToken(requestedQuality: requestedQuality)
        return
            "unavailable|\(bvid)|\(cid)|\(requestedQuality)|credential=\(snapshot.playbackCredentialVersion)|source=\(snapshot.playbackStreamSourcePreference.cachePlatform)|codec=\(codecToken)|decode=\(hardwareToken)|network=\(networkToken)"
    }

    func logPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        start: CFTimeInterval,
        data: PlayURLData? = nil,
        error: Error? = nil
    ) {
        let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
        let variants = data?.playVariants ?? []
        let playableVariants = variants.filter(\.isPlayable)
        let qualities =
            playableVariants
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        let qualitySummary = qualities.isEmpty ? "-" : qualities
        let rawSummary = data?.rawPlayURLSummary ?? "-"
        let errorMessage = error?.localizedDescription ?? ""

        if error != nil {
            PlayerMetricsLog.logger.error(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) error=\(errorMessage, privacy: .public)"
            )
        } else {
            PlayerMetricsLog.logger.info(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) variants=\(variants.count, privacy: .public) playable=\(playableVariants.count, privacy: .public) highest=\(data?.highestPlayableQuality ?? 0, privacy: .public) durl=\((data?.durl?.isEmpty == false), privacy: .public) dash=\((data?.dash?.video?.isEmpty == false), privacy: .public) qualities=\(qualitySummary, privacy: .public) raw=\(rawSummary, privacy: .public)"
            )
        }
    }

    private func qualitySummary(_ variants: [PlayVariant]) -> String {
        let qualities =
            variants
            .filter(\.isPlayable)
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        return qualities.isEmpty ? "-" : qualities
    }

    func requirePlayURLData(_ response: BiliResponse<PlayURLData>, requirePlayablePayload: Bool = false) throws
        -> PlayURLData
    {
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        if let code = data.code, code != 0 {
            throw BiliAPIError.api(code: code, message: data.message)
        }
        if requirePlayablePayload, data.playVariants.isEmpty {
            if data.hasAnyPlayURLPayload {
                throw BiliAPIError.unsupportedHardwarePlayback(
                    "播放接口已返回地址，但没有可用的 HEVC/AAC 硬解组合（\(data.rawPlayURLSummary)）"
                )
            }
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

}

extension JSONDecoder {
    nonisolated static var bili: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}

extension Float {
    fileprivate static var userInitiated: Float { URLSessionTask.highPriority }
    fileprivate static var utility: Float { URLSessionTask.defaultPriority }
    fileprivate static var background: Float { URLSessionTask.lowPriority }
}

nonisolated struct PiliPlusWebpageHedge: Sendable {
    let scheduledAt: CFTimeInterval
    let delayNanoseconds: UInt64
    let task: Task<PlayURLData, Error>
}

private nonisolated final class PendingTaskWaiter<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func succeed(_ value: Value) {
        complete(.success(value))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

nonisolated private struct FrontendFingerprintData: Decodable {
    let buvid3: String?

    enum CodingKeys: String, CodingKey {
        case buvid3 = "b_3"
    }
}

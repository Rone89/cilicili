import CryptoKit
import Foundation
import OSLog
import QuartzCore
import Security

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

nonisolated final class BiliAPIClient {
    let baseURL = URL(string: "https://api.bilibili.com")!
    let appURL = URL(string: "https://app.bilibili.com")!
    private let commentURL = URL(string: "https://comment.bilibili.com")!
    private static let appRecommendProfiles: [BiliAppSigner.Profile] = [.androidHD, .androidPhone]
    private static let primaryAppRecommendProfile: BiliAppSigner.Profile = .androidHD
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private static let recommendLogger = Logger(subsystem: "cc.bili", category: "HomeRecommend")
    private let session: URLSession
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore
    private let homeRecommendDiagnosticsStore: HomeRecommendDiagnosticsStore
    private let playURLCache: PlayURLCache
    private let state = BiliAPIClientState()
    static let uploaderLogger = Logger(subsystem: "cc.bili", category: "Uploader")
    private static let historyLogger = Logger(subsystem: "cc.bili", category: "History")

    fileprivate struct TargetQualityUnavailableError: LocalizedError, Sendable {
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

    private func cookieHeader() async -> String {
        let snapshot = await requestSnapshot()
        return snapshot.cookieHeader
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

    func prewarmPlaybackSigningKeys() async {
        _ = try? await fetchWBIKeys(priority: .utility)
    }

    func refreshPlaybackSigningKeys() async throws -> WBIKeys {
        await state.clearWBIKeys()
        return try await fetchWBIKeys(
            priority: .userInitiated,
            forcesNetworkRefresh: true
        )
    }

    func signedWBIQuery(_ query: [String: String]) async throws -> [String: String] {
        let keys = try await fetchWBIKeys(priority: .userInitiated)
        return WBISigner.sign(query, keys: keys)
    }

    func prewarmStartupResources() async {
        async let keys: Void = prewarmPlaybackSigningKeys()
        async let nav: NavUserInfo? = try? fetchNavUser()
        _ = await (keys, nav)
    }

    func resetHomeRecommendState() async {
        await state.clearHomeRecommendState()
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

    func fetchRecommendFeed(freshIndex: Int = 0, limit: Int? = nil) async throws -> [VideoItem] {
        let snapshot = await requestSnapshot()
        let feedSource = snapshot.homeRecommendFeedSourcePreference
        let requestLimit = Self.normalizedRecommendLimit(limit)

        let taskKey = [
            "recommend",
            feedSource.rawValue,
            "idx-\(freshIndex)",
            "limit-\(requestLimit.map(String.init) ?? "default")",
            "guest-\(snapshot.guestModeEnabled ? "1" : "0")",
            "identity-\(snapshot.homeRecommendIdentityKey)",
            "accessKey-\(snapshot.appAccessKey == nil ? "0" : "1")"
        ].joined(separator: "|")
        if let task = await state.videoListTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            switch feedSource {
            case .web:
                let videos = try await fetchWebRecommendFeed(
                    freshIndex: freshIndex,
                    limit: requestLimit
                )
                Self.recommendLogger.info(
                    "source=web endpoint=/x/web-interface/wbi/index/top/feed/rcmd freshIndex=\(freshIndex, privacy: .public) limit=\(requestLimit ?? 0, privacy: .public) count=\(videos.count, privacy: .public)"
                )
                return videos
            case .app:
                let fallbackContext: RecommendFallbackContext
                do {
                    let videos = try await fetchAppRecommendFeed(
                        freshIndex: freshIndex,
                        limit: requestLimit
                    )
                    if !videos.isEmpty {
                        Self.recommendLogger.info(
                            "source=app primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) signed=1 endpoint=/x/v2/feed/index host=app.bilibili.com freshIndex=\(freshIndex, privacy: .public) limit=\(requestLimit ?? 0, privacy: .public) count=\(videos.count, privacy: .public)"
                        )
                        return videos
                    }
                    Self.recommendLogger.error(
                        "source=app fallback=web reason=empty primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) freshIndex=\(freshIndex, privacy: .public)"
                    )
                    fallbackContext = RecommendFallbackContext(
                        fromSource: .app,
                        reason: "app-empty",
                        errorMessage: nil
                    )
                } catch {
                    Self.recommendLogger.error(
                        "source=app fallback=web reason=error primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) freshIndex=\(freshIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    fallbackContext = RecommendFallbackContext(
                        fromSource: .app,
                        reason: "app-error",
                        errorMessage: error.localizedDescription
                    )
                }
                let fallbackVideos = try await fetchWebRecommendFeed(
                    freshIndex: freshIndex,
                    limit: requestLimit,
                    fallbackContext: fallbackContext
                )
                Self.recommendLogger.info(
                    "source=web fallbackFrom=app endpoint=/x/web-interface/wbi/index/top/feed/rcmd freshIndex=\(freshIndex, privacy: .public) count=\(fallbackVideos.count, privacy: .public)"
                )
                return fallbackVideos
            }
        }
        await state.setVideoListTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await state.clearVideoListTask(for: taskKey)
            return videos
        } catch {
            await state.clearVideoListTask(for: taskKey)
            throw error
        }
    }

    private func fetchWebRecommendFeed(
        freshIndex: Int,
        limit: Int?,
        fallbackContext: RecommendFallbackContext? = nil
    ) async throws -> [VideoItem] {
        let snapshot = await requestSnapshot()
        let cookieHeader = snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : snapshot.cookieHeader
        let authDiagnostics = Self.recommendAuthDiagnostics(
            cookieHeader: cookieHeader,
            accessKey: nil,
            isLoggedIn: snapshot.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        let keys = try await fetchWBIKeys(priority: .userInitiated)
        let pageSize = Self.recommendRequestPageSize(limit)
        let signed = WBISigner.sign([
            "version": "1",
            "homepage_ver": "1",
            "feed_version": "V8",
            "ps": String(pageSize),
            "fresh_idx": String(freshIndex),
            "brush": String(freshIndex),
            "fresh_idx_1h": String(freshIndex),
            "fresh_type": "4"
        ], keys: keys)

        await homeRecommendDiagnosticsStore.recordRequest(HomeRecommendDiagnosticsSnapshot(
            status: .requesting,
            source: .web,
            fallbackFromSource: fallbackContext?.fromSource,
            fallbackReason: fallbackContext?.reason,
            fallbackErrorMessage: fallbackContext?.errorMessage,
            fallbackAt: fallbackContext == nil ? nil : Date(),
            endpoint: "/x/web-interface/wbi/index/top/feed/rcmd",
            profile: "web-wbi",
            authMode: authDiagnostics.mode,
            isLoggedIn: authDiagnostics.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled,
            hasAccessKey: false,
            hasSESSDATA: authDiagnostics.hasSESSDATA,
            hasDedeUserID: authDiagnostics.hasDedeUserID,
            hasBuvid: authDiagnostics.hasBuvid,
            hasBuvidFP: authDiagnostics.hasBuvidFP,
            identityKey: snapshot.homeRecommendIdentityKey,
            requestedIndex: freshIndex,
            nextIndex: nil,
            nextIndexSource: nil,
            fingerprintSource: nil,
            sessionSource: nil,
            appKeyHeader: nil,
            signedAppKey: nil,
            appVersion: nil,
            build: nil,
            network: nil,
            requestProfile: nil,
            requestStartedAt: Date(),
            responseFinishedAt: nil,
            rawCount: nil,
            videoCardCount: nil,
            videoCount: nil,
            liveCardCount: nil,
            droppedCardCount: nil,
            recommendReasonCount: nil,
            errorMessage: nil
        ))

        let response: BiliResponse<RecommendFeedData>
        do {
            response = try await get(
                base: baseURL,
                path: "/x/web-interface/wbi/index/top/feed/rcmd",
                query: signed,
                cookieHeader: await guestModeCookieHeader(),
                cachePolicy: .reloadIgnoringLocalCacheData,
                responseCachePolicy: .brief
            )
        } catch {
            await homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: error.localizedDescription
            )
            throw error
        }
        guard response.code == 0 else {
            await homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: response.displayMessage
            )
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let allVideos = response.payload?.feedItems.compactMap { $0.asVideoItem() } ?? []
        let videos = Self.limitedRecommendVideos(allVideos, limit: limit)
        await homeRecommendDiagnosticsStore.recordResponse(
            status: .succeeded,
            nextIndex: nil,
            nextIndexSource: nil,
            rawCount: response.payload?.feedItems.count ?? 0,
            videoCardCount: response.payload?.feedItems.filter(\.isVideoCard).count ?? videos.count,
            videoCount: videos.count,
            liveCardCount: nil,
            droppedCardCount: max(0, (response.payload?.feedItems.count ?? allVideos.count) - allVideos.count),
            recommendReasonCount: videos.filter { $0.recommendReason?.isEmpty == false }.count
        )
        return videos
    }

    private func fetchAppRecommendFeed(freshIndex: Int, limit: Int?) async throws -> [VideoItem] {
        let snapshot = await requestSnapshot()
        let cookieHeader = snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : snapshot.cookieHeader
        let accessKey = snapshot.guestModeEnabled ? nil : snapshot.appAccessKey
        let authDiagnostics = Self.recommendAuthDiagnostics(
            cookieHeader: cookieHeader,
            accessKey: accessKey,
            isLoggedIn: snapshot.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled
        )
        let requestedIndex: Int
        if freshIndex <= 0 {
            await state.setAppRecommendFeedIndex(nil)
            requestedIndex = 0
        } else {
            requestedIndex = await state.appRecommendFeedIndex(defaulting: freshIndex)
        }

        var lastError: Error?
        for (attemptIndex, profile) in Self.appRecommendProfiles.enumerated() {
            do {
                let videos = try await fetchAppRecommendFeed(
                    requestedIndex: requestedIndex,
                    cookieHeader: cookieHeader,
                    accessKey: accessKey,
                    limit: limit,
                    authDiagnostics: authDiagnostics,
                    snapshot: snapshot,
                    profile: profile,
                    fallbackProfile: attemptIndex == 0 ? nil : Self.appRecommendProfiles.first
                )
                if !videos.isEmpty || attemptIndex == Self.appRecommendProfiles.count - 1 {
                    return videos
                }
                Self.recommendLogger.error(
                    "source=app profileFallback reason=empty from=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public)"
                )
            } catch {
                lastError = error
                Self.recommendLogger.error(
                    "source=app profileFallback reason=error from=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw lastError ?? BiliAPIError.missingPayload
    }

    private func fetchAppRecommendFeed(
        requestedIndex: Int,
        cookieHeader: String,
        accessKey: String?,
        limit: Int?,
        authDiagnostics: RecommendAuthDiagnostics,
        snapshot: RequestSnapshot,
        profile: BiliAppSigner.Profile,
        fallbackProfile: BiliAppSigner.Profile?
    ) async throws -> [VideoItem] {
        let query = Self.piliPlusStyleAppRecommendQuery(
            freshIndex: requestedIndex,
            accessKey: accessKey,
            limit: limit,
            profile: profile
        )
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        await homeRecommendDiagnosticsStore.recordRequest(HomeRecommendDiagnosticsSnapshot(
            status: .requesting,
            source: .app,
            endpoint: "/x/v2/feed/index",
            profile: profile.displayName,
            authMode: authDiagnostics.mode,
            isLoggedIn: authDiagnostics.isLoggedIn,
            guestModeEnabled: snapshot.guestModeEnabled,
            hasAccessKey: authDiagnostics.hasAccessKey,
            hasSESSDATA: authDiagnostics.hasSESSDATA,
            hasDedeUserID: authDiagnostics.hasDedeUserID,
            hasBuvid: authDiagnostics.hasBuvid,
            hasBuvidFP: authDiagnostics.hasBuvidFP,
            identityKey: snapshot.homeRecommendIdentityKey,
            requestedIndex: requestedIndex,
            nextIndex: nil,
            nextIndexSource: nil,
            fingerprintSource: headerContext.fingerprintSource,
            sessionSource: headerContext.sessionSource,
            appKeyHeader: headerContext.appKeyHeader,
            signedAppKey: profile.appKey,
            appVersion: profile.appVersion,
            build: profile.build,
            network: query["network"],
            requestProfile: Self.appRecommendRequestProfileSummary(
                query: query,
                headerContext: headerContext,
                profile: profile,
                fallbackProfile: fallbackProfile
            ),
            requestStartedAt: Date(),
            responseFinishedAt: nil,
            rawCount: nil,
            videoCardCount: nil,
            videoCount: nil,
            liveCardCount: nil,
            droppedCardCount: nil,
            recommendReasonCount: nil,
            errorMessage: nil
        ))
        Self.recommendLogger.info(
            "source=app request endpoint=/x/v2/feed/index host=app.bilibili.com profile=\(profile.displayName, privacy: .public) signed=1 auth=\(authDiagnostics.mode, privacy: .public) loggedIn=\(authDiagnostics.isLoggedIn, privacy: .public) hasAccessKey=\(authDiagnostics.hasAccessKey, privacy: .public) hasSESSDATA=\(authDiagnostics.hasSESSDATA, privacy: .public) hasDedeUserID=\(authDiagnostics.hasDedeUserID, privacy: .public) hasBuvid=\(authDiagnostics.hasBuvid, privacy: .public) hasBuvidFP=\(authDiagnostics.hasBuvidFP, privacy: .public) idx=\(requestedIndex, privacy: .public) pull=\(requestedIndex == 0 ? "true" : "false", privacy: .public) fp=\(headerContext.fingerprintSource, privacy: .public) session=\(headerContext.sessionSource, privacy: .public) cacheIdentity=\(snapshot.homeRecommendIdentityKey, privacy: .public) trace=per-request cache=snapshot-bypassed"
        )
        let response: BiliResponse<RecommendFeedData>
        do {
            response = try await get(
                base: appURL,
                path: "/x/v2/feed/index",
                query: BiliAppSigner.sign(query, profile: profile),
                referer: "https://www.bilibili.com",
                userAgent: profile.userAgent,
                cookieHeader: cookieHeader,
                additionalHeaders: headerContext.headers,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        } catch {
            await homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: error.localizedDescription
            )
            throw error
        }
        guard response.code == 0 else {
            await homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: response.displayMessage
            )
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let payload = response.payload else {
            await homeRecommendDiagnosticsStore.recordResponse(
                status: .succeeded,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: 0,
                videoCardCount: 0,
                videoCount: 0,
                liveCardCount: 0,
                droppedCardCount: 0,
                recommendReasonCount: 0
            )
            return []
        }
        let allVideos = payload.feedItems.compactMap { $0.asVideoItem() }
        let videos = Self.limitedRecommendVideos(allVideos, limit: limit)
        let nextIndexResult = payload.appNextIndexResult(after: requestedIndex)
        let nextIndex = nextIndexResult.value
        let videoCardCount = payload.feedItems.filter(\.isVideoCard).count
        let liveCardCount = payload.feedItems.filter {
            let kind = $0.resolvedCardKind
            return kind == "live" || kind == "live_room" || kind == "live_room_rcmd"
        }.count
        let droppedCardCount = max(0, payload.feedItems.count - videoCardCount)
        let recommendReasonCount = videos.filter { $0.recommendReason?.isEmpty == false }.count
        await state.setAppRecommendFeedIndex(nextIndex)
        await homeRecommendDiagnosticsStore.recordResponse(
            status: .succeeded,
            nextIndex: nextIndex,
            nextIndexSource: nextIndexResult.source,
            rawCount: payload.feedItems.count,
            videoCardCount: videoCardCount,
            videoCount: videos.count,
            liveCardCount: liveCardCount,
            droppedCardCount: droppedCardCount,
            recommendReasonCount: recommendReasonCount
        )
        Self.recommendLogger.info(
            "source=app response endpoint=/x/v2/feed/index auth=\(authDiagnostics.mode, privacy: .public) profile=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public) nextIdx=\(nextIndex ?? -1, privacy: .public) nextIdxSource=\(nextIndexResult.source ?? "-", privacy: .public) rawCount=\(payload.feedItems.count, privacy: .public) videoCardCount=\(videoCardCount, privacy: .public) videoCount=\(videos.count, privacy: .public) liveCardCount=\(liveCardCount, privacy: .public) droppedCardCount=\(droppedCardCount, privacy: .public) recommendReasonCount=\(recommendReasonCount, privacy: .public)"
        )
        return videos
    }

    private static func piliPlusStyleAppRecommendQuery(
        freshIndex: Int,
        accessKey: String?,
        limit: Int?,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        var query: [String: String]
        switch profile {
        case .androidHD:
            query = [
                "build": profile.build,
                "c_locale": "zh_CN",
                "channel": profile.channel,
                "column": "4",
                "device": profile.device,
                "device_name": "android",
                "device_type": "0",
                "disable_rcmd": "0",
                "flush": "5",
                "fnval": "976",
                "fnver": "0",
                "force_host": "2",
                "fourk": "1",
                "guidance": "0",
                "https_url_req": "0",
                "idx": String(freshIndex),
                "login_event": accessKey == nil ? "0" : "1",
                "mobi_app": profile.mobiApp,
                "network": "wifi",
                "platform": profile.platform,
                "player_net": "1",
                "pull": freshIndex == 0 ? "true" : "false",
                "qn": "32",
                "recsys_mode": "0",
                "s_locale": "zh_CN",
                "splash_id": "",
                "statistics": profile.statistics,
                "voice_balance": "0"
            ]
        case .androidPhone, .androidLogin, .androidTV:
            query = [
                "idx": String(freshIndex),
                "flush": "5",
                "pull": freshIndex == 0 ? "true" : "false",
                "device": profile.device,
                "login_event": accessKey == nil ? "0" : "1",
                "network": "wifi",
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
                "build": profile.build
            ]
        }
        if let limit {
            let pageSize = String(recommendRequestPageSize(limit))
            query["ps"] = pageSize
            query["page_size"] = pageSize
        }
        if let accessKey {
            query["access_key"] = accessKey
        }
        return query
    }

    private static func normalizedRecommendLimit(_ limit: Int?) -> Int? {
        guard let limit else { return nil }
        return max(1, min(limit, 50))
    }

    private static func recommendRequestPageSize(_ limit: Int?) -> Int {
        normalizedRecommendLimit(limit) ?? 20
    }

    private static func limitedRecommendVideos(_ videos: [VideoItem], limit: Int?) -> [VideoItem] {
        guard let limit = normalizedRecommendLimit(limit), videos.count > limit else {
            return videos
        }
        return Array(videos.prefix(limit))
    }

    private static let appRecommendHydrationCandidateLimit = 24
    private static let appRecommendHydrationConcurrencyLimit = 6

    struct AppRecommendHeaderContext {
        let headers: [String: String]
        let fingerprintSource: String
        let sessionSource: String
        let appKeyHeader: String
    }

    private struct RecommendFallbackContext {
        let fromSource: HomeRecommendFeedSourcePreference
        let reason: String
        let errorMessage: String?
    }

    private struct RecommendAuthDiagnostics {
        let mode: String
        let isLoggedIn: Bool
        let hasSESSDATA: Bool
        let hasAccessKey: Bool
        let hasDedeUserID: Bool
        let hasBuvid: Bool
        let hasBuvidFP: Bool
    }

    static func piliPodStyleAppRecommendHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> AppRecommendHeaderContext {
        let buvid = cookieValue(named: "buvid3", in: cookieHeader)
            ?? cookieValue(named: "buvid4", in: cookieHeader)
            ?? "11111111111111111111111111111111"
        let cookieFingerprint = cookieValue(named: "buvid_fp", in: cookieHeader)
            ?? cookieValue(named: "buvid_fp_plain", in: cookieHeader)
        let fingerprint = cookieFingerprint ?? stableHexToken(seed: buvid, length: 64)
        let cookieSession = cookieValue(named: "b_lsid", in: cookieHeader)
            .map { stableHexToken(seed: $0, length: 8) }
        let sessionID = cookieSession ?? stableHexToken(seed: buvid, length: 8)
        let headers = [
            "buvid": buvid,
            "fp_local": fingerprint,
            "fp_remote": fingerprint,
            "session_id": sessionID,
            "env": "prod",
            "app-key": profile.appKeyHeader,
            "x-bili-trace-id": piliPlusTraceID(),
            "x-bili-aurora-eid": "",
            "x-bili-aurora-zone": "",
            "bili-http-engine": "cronet"
        ]
        return AppRecommendHeaderContext(
            headers: headers,
            fingerprintSource: cookieFingerprint == nil ? "generated" : "cookie",
            sessionSource: cookieSession == nil ? "generated" : "cookie",
            appKeyHeader: profile.appKeyHeader
        )
    }

    static func uploaderAppHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        piliPodStyleAppRecommendHeaders(cookieHeader: cookieHeader, profile: profile).headers
    }

    static func interactionAppHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        piliPodStyleAppRecommendHeaders(cookieHeader: cookieHeader, profile: profile).headers
    }

    private static func appRecommendRequestProfileSummary(
        query: [String: String],
        headerContext: AppRecommendHeaderContext,
        profile: BiliAppSigner.Profile,
        fallbackProfile: BiliAppSigner.Profile?
    ) -> String {
        [
            "profile=\(profile.displayName)",
            "fallbackFrom=\(fallbackProfile?.displayName ?? "-")",
            "mobi_app=\(profile.mobiApp)",
            "platform=\(profile.platform)",
            "appver=\(profile.appVersion)",
            "build=\(profile.build)",
            "channel=\(profile.channel)",
            "device=\(query["device"] ?? "-")",
            "column=\(query["column"] ?? "-")",
            "disableRcmd=\(query["disable_rcmd"] ?? "-")",
            "network=\(query["network"] ?? "-")",
            "headerAppKey=\(headerContext.appKeyHeader)",
            "signedAppKey=\(profile.appKey)",
            "accessKey=\(query["access_key"] == nil ? "0" : "1")",
            "statistics=\(query["statistics"] == nil ? "0" : "1")"
        ].joined(separator: " ")
    }

    private static func recommendAuthDiagnostics(
        cookieHeader: String,
        accessKey: String?,
        isLoggedIn: Bool,
        guestModeEnabled: Bool
    ) -> RecommendAuthDiagnostics {
        let hasAccessKey = accessKey?.isEmpty == false
        let hasSESSDATA = cookieValue(named: "SESSDATA", in: cookieHeader) != nil
        let hasDedeUserID = cookieValue(named: "DedeUserID", in: cookieHeader) != nil
        let hasBuvid = cookieValue(named: "buvid3", in: cookieHeader) != nil
            || cookieValue(named: "buvid4", in: cookieHeader) != nil
        let hasBuvidFP = cookieValue(named: "buvid_fp", in: cookieHeader) != nil
            || cookieValue(named: "buvid_fp_plain", in: cookieHeader) != nil
        let mode: String
        if guestModeEnabled {
            mode = "guest"
        } else if hasAccessKey {
            mode = "app-access-key"
        } else if hasSESSDATA {
            mode = "cookie-only"
        } else {
            mode = "anon"
        }
        return RecommendAuthDiagnostics(
            mode: mode,
            isLoggedIn: isLoggedIn,
            hasSESSDATA: hasSESSDATA,
            hasAccessKey: hasAccessKey,
            hasDedeUserID: hasDedeUserID,
            hasBuvid: hasBuvid,
            hasBuvidFP: hasBuvidFP
        )
    }

    private static func piliPlusTraceID() -> String {
        "\(stableHexToken(seed: UUID().uuidString, length: 32)):\(stableHexToken(seed: UUID().uuidString, length: 16)):0:0"
    }

    private static func stableHexToken(seed: String, length: Int) -> String {
        let hex = seed.unicodeScalars.map { scalar in
            String(format: "%02x", scalar.value & 0xff)
        }.joined()
        var value = hex.isEmpty ? "0123456789abcdef" : hex
        while value.count < length {
            value += value
        }
        return String(value.prefix(length))
    }

    func hydrateRecommendMetadataIfNeeded(_ videos: [VideoItem]) async -> [VideoItem] {
        let hydrationCandidates = Array(videos.enumerated().filter { _, video in
            video.aid != nil && (video.pubdate == nil || video.owner?.face == nil)
        }.prefix(Self.appRecommendHydrationCandidateLimit))
        guard !hydrationCandidates.isEmpty else { return videos }

        let hydratedPairs = await withTaskGroup(of: (Int, VideoItem)?.self) { group in
            var nextCandidateIndex = 0
            let initialTaskCount = min(Self.appRecommendHydrationConcurrencyLimit, hydrationCandidates.count)

            for _ in 0..<initialTaskCount {
                let candidate = hydrationCandidates[nextCandidateIndex]
                nextCandidateIndex += 1
                group.addTask { [self] in
                    let (index, video) = candidate
                    guard let aid = video.aid else { return nil }
                    guard let fullDetail = try? await fetchVideoDetail(aid: aid) else { return nil }
                    return (index, video.mergingFilledValues(from: fullDetail))
                }
            }

            var pairs = [(Int, VideoItem)]()
            while let pair = await group.next() {
                if let pair {
                    pairs.append(pair)
                }
                if nextCandidateIndex < hydrationCandidates.count {
                    let candidate = hydrationCandidates[nextCandidateIndex]
                    nextCandidateIndex += 1
                    group.addTask { [self] in
                        let (index, video) = candidate
                        guard let aid = video.aid else { return nil }
                        guard let fullDetail = try? await fetchVideoDetail(aid: aid) else { return nil }
                        return (index, video.mergingFilledValues(from: fullDetail))
                    }
                }
            }
            return pairs
        }

        guard !hydratedPairs.isEmpty else { return videos }
        var mergedVideos = videos
        for (index, video) in hydratedPairs where mergedVideos.indices.contains(index) {
            mergedVideos[index] = video
        }
        return mergedVideos
    }

    func fetchPopularVideos(page: Int = 1) async throws -> [VideoItem] {
        let taskKey = "popular|\(page)"
        if let task = await state.videoListTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<BiliPage<VideoItem>> = try await get(
                base: baseURL,
                path: "/x/web-interface/popular",
                query: [
                    "pn": String(page),
                    "ps": "20"
                ],
                responseCachePolicy: .brief
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            return response.payload?.list ?? []
        }
        await state.setVideoListTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await state.clearVideoListTask(for: taskKey)
            return videos
        } catch {
            await state.clearVideoListTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoDetail(bvid: String, bypassesCache: Bool = false) async throws -> VideoItem {
        let snapshot = await requestSnapshot()
        if bypassesCache {
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["bvid": bvid],
                cookieHeader: snapshot.cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData,
                priority: URLSessionTask.highPriority
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        let taskKey = "bvid:\(bvid)|credential:\(snapshot.playbackCredentialVersion)"
        if let task = await state.videoDetailTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["bvid": bvid],
                cookieHeader: snapshot.cookieHeader,
                responseCachePolicy: .detail
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await state.setVideoDetailTask(task, for: taskKey)
        do {
            let item = try await task.value
            await state.clearVideoDetailTask(for: taskKey)
            return item
        } catch {
            await state.clearVideoDetailTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoDetail(aid: Int) async throws -> VideoItem {
        let snapshot = await requestSnapshot()
        let taskKey = "aid:\(aid)|credential:\(snapshot.playbackCredentialVersion)"
        if let task = await state.videoDetailTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["aid": String(aid)],
                cookieHeader: snapshot.cookieHeader,
                responseCachePolicy: .detail
            )
            guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await state.setVideoDetailTask(task, for: taskKey)
        do {
            let item = try await task.value
            await state.clearVideoDetailTask(for: taskKey)
            return item
        } catch {
            await state.clearVideoDetailTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoRelated(bvid: String) async throws -> [VideoItem] {
        let response: BiliResponse<[VideoItem]> = try await get(
            base: baseURL,
            path: "/x/web-interface/archive/related",
            query: [
                "bvid": bvid,
                "pn": "1",
                "ps": "40"
            ],
            userAgent: Self.webUserAgent,
            cookieHeader: await guestModeCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload ?? []
    }

    func fetchVideoShot(bvid: String, cid: Int) async throws -> VideoShotMetadata {
        let normalizedBVID = bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBVID.isEmpty, cid > 0 else { throw BiliAPIError.missingPayload }
        let snapshot = await requestSnapshot(purpose: .playback)
        let response: BiliResponse<VideoShotMetadata> = try await get(
            base: baseURL,
            path: "/x/player/videoshot",
            query: [
                "bvid": normalizedBVID,
                "cid": String(cid),
                "index": "1"
            ],
            referer: "https://www.bilibili.com/video/\(normalizedBVID)",
            userAgent: Self.webUserAgent,
            cookieHeader: snapshot.cookieHeader,
            responseCachePolicy: .long,
            priority: .utility
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let metadata = response.payload, metadata.isUsable else {
            throw BiliAPIError.missingPayload
        }
        return metadata
    }

    func fetchDanmaku(cid: Int) async throws -> [DanmakuItem] {
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
                return cached
            }

            var request = try await makeRequest(
                base: commentURL,
                path: "/\(cid).xml",
                query: [:],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: await guestModeCookieHeader(),
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/xml,text/xml,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await data(for: request, priority: .utility)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }
            guard !data.isEmpty else { throw BiliAPIError.emptyData }

            let items = try DanmakuXMLParser(cid: cid).parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(items, for: cid, segmentIndex: 0)
            return items
        }
    }

    func fetchDanmakuSegment(cid: Int, segmentIndex: Int) async throws -> [DanmakuItem] {
        let normalizedSegmentIndex = max(1, segmentIndex)
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
            for: cid,
            segmentIndex: normalizedSegmentIndex
        ) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
                for: cid,
                segmentIndex: normalizedSegmentIndex
            ) {
                return cached
            }

            var request = try await makeRequest(
                base: baseURL,
                path: "/x/v2/dm/web/seg.so",
                query: [
                    "type": "1",
                    "oid": String(cid),
                    "segment_index": String(normalizedSegmentIndex)
                ],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: await guestModeCookieHeader(),
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await data(for: request, priority: .utility)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }

            let items = try DanmakuSegmentProtobufParser(
                cid: cid,
                segmentIndex: normalizedSegmentIndex
            )
            .parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(
                items,
                for: cid,
                segmentIndex: normalizedSegmentIndex
            )
            return items
        }
    }

    func reportVideoHistory(
        aid: Int?,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        bvid: String? = nil
    ) async throws {
        let snapshot = await requestSnapshot(purpose: .historyWrite)
        guard snapshot.isAccountPurposeEnabled else { return }
        var webError: Error?
        if let csrf = snapshot.csrfToken, !csrf.isEmpty, snapshot.isLoggedIn {
            do {
                try await reportVideoHeartbeatWithWeb(
                    aid: aid,
                    bvid: bvid,
                    cid: cid,
                    progress: progress,
                    csrf: csrf,
                    cookieHeader: snapshot.cookieHeader
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                webError = error
                Self.historyLogger.error("historyReport webFailed fallback=history aid=\(aid ?? 0, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                if let aid, aid > 0 {
                    do {
                        try await reportVideoHistoryWithWeb(
                            aid: aid,
                            cid: cid,
                            progress: progress,
                            duration: duration,
                            csrf: csrf,
                            cookieHeader: snapshot.cookieHeader
                        )
                        return
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        webError = error
                    }
                }
            }
        }

        if let aid, aid > 0, let accessKey = snapshot.appAccessKey, !accessKey.isEmpty {
            do {
                try await reportVideoHistoryWithAppAccessKey(
                    aid: aid,
                    cid: cid,
                    progress: progress,
                    duration: duration,
                    accessKey: accessKey,
                    cookieHeader: snapshot.cookieHeader
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.historyLogger.error("historyReport appFailed aid=\(aid, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        if let webError {
            throw webError
        }
        throw BiliAPIError.missingSESSDATA
    }

    private func reportVideoHistoryWithWeb(
        aid: Int,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        csrf: String,
        cookieHeader: String
    ) async throws {
        var body = [
            "aid": String(aid),
            "progress": String(max(0, Int(progress))),
            "type": "3",
            "csrf": csrf,
            "gaia_source": "web_normal",
            "ga": "1"
        ]
        if let cid, cid > 0 {
            body["cid"] = String(cid)
        }
        if let duration, duration > 0 {
            body["duration"] = String(Int(duration))
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/history/report",
            body: body,
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    private func reportVideoHeartbeatWithWeb(
        aid: Int?,
        bvid: String?,
        cid: Int?,
        progress: TimeInterval,
        csrf: String,
        cookieHeader: String
    ) async throws {
        let normalizedBVID = bvid?.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = [
            "played_time": String(max(0, Int(progress))),
            "type": "3",
            "csrf": csrf
        ]
        if let normalizedBVID, !normalizedBVID.isEmpty {
            body["bvid"] = normalizedBVID
        } else if let aid, aid > 0 {
            body["aid"] = String(aid)
        } else {
            throw BiliAPIError.missingPayload
        }
        if let cid, cid > 0 {
            body["cid"] = String(cid)
        }
        let referer: String
        if let normalizedBVID, !normalizedBVID.isEmpty {
            referer = "https://www.bilibili.com/video/\(normalizedBVID)"
        } else if let aid, aid > 0 {
            referer = "https://www.bilibili.com/video/av\(aid)"
        } else {
            referer = "https://www.bilibili.com"
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/click-interface/web/heartbeat",
            body: body,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    private func reportVideoHistoryWithAppAccessKey(
        aid: Int,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        accessKey: String,
        cookieHeader: String
    ) async throws {
        let profile = BiliAppSigner.Profile.androidLogin
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        var fields = [
            "access_key": accessKey,
            "aid": String(aid),
            "progress": String(max(0, Int(progress))),
            "type": "3",
            "gaia_source": "app_normal"
        ]
        if let cid, cid > 0 {
            fields["cid"] = String(cid)
        }
        if let duration, duration > 0 {
            fields["duration"] = String(Int(duration))
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postSignedAPIForm(
            path: "/x/v2/history/report",
            fields: fields,
            profile: profile,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    func fetchOfficialVideoListenPlaylist(
        aid: Int,
        cid: Int?,
        cursor: String? = nil,
        sortOrder: VideoListenPlaylistSortOrder = .normal
    ) async throws -> BiliListenerPlaylistPage {
        guard aid > 0 else { throw BiliListenerPlaylistError.invalidAnchor }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedCursor?.isEmpty != false, (cid ?? 0) <= 0 {
            throw BiliListenerPlaylistError.invalidAnchor
        }

        let snapshot = await requestSnapshot(purpose: .playback)
        guard !snapshot.guestModeEnabled,
              let accessKey = snapshot.appAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessKey.isEmpty
        else {
            throw BiliListenerPlaylistError.missingAccessKey
        }

        let profile = BiliAppSigner.Profile.androidHD
        let cookieHeader = snapshot.cookieHeader
        let buvid = Self.cookieValue(named: "buvid3", in: cookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: cookieHeader)
            ?? Self.cookieValue(named: "buvid3", in: snapshot.anonymousCookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: snapshot.anonymousCookieHeader)
            ?? ""
        let headers = BiliListenerPlaylistCodec.grpcHeaders(
            accessKey: accessKey,
            buvid: buvid,
            networkClass: PlaybackEnvironment.current.networkClass,
            traceID: Self.piliPlusTraceID()
        )
        let message = try BiliListenerPlaylistCodec.encodeRequest(
            aid: aid,
            cid: cid,
            cursor: normalizedCursor,
            sortOrder: sortOrder
        )
        var request = try await makeRequest(
            base: appURL,
            path: BiliListenerPlaylistCodec.endpointPath,
            query: [:],
            referer: "https://www.bilibili.com/video/av\(aid)",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: headers,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = BiliListenerPlaylistCodec.frame(message)

        let (data, response) = try await self.data(
            for: request,
            priority: .userInitiated,
            retryPolicy: .api
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BiliListenerPlaylistError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let biliStatus = httpResponse.value(forHTTPHeaderField: "bili-status-code")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let biliStatus, biliStatus != 0 {
            let message = httpResponse.value(forHTTPHeaderField: "bili-status-message")
                ?? httpResponse.value(forHTTPHeaderField: "grpc-message")
            throw BiliListenerPlaylistError.grpcStatus(
                biliStatus,
                message?.removingPercentEncoding ?? message
            )
        }

        let grpcStatus = httpResponse.value(forHTTPHeaderField: "grpc-status")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let grpcStatus, grpcStatus != 0 {
            let message = httpResponse.value(forHTTPHeaderField: "grpc-message")
            throw BiliListenerPlaylistError.grpcStatus(
                grpcStatus,
                message?.removingPercentEncoding ?? message
            )
        }

        guard !data.isEmpty else { throw BiliListenerPlaylistError.invalidResponse }
        let responseMessage = try BiliListenerPlaylistCodec.unframe(data)
        return try BiliListenerPlaylistCodec.decodeResponse(responseMessage)
    }

    func fetchPgcSeasonInfo(seasonID: Int?, epID: Int? = nil) async throws -> PgcSeasonInfo {
        var candidates = [(query: [String: String], referer: String)]()
        if let epID, epID > 0 {
            candidates.append((
                query: ["ep_id": String(epID)],
                referer: "https://www.bilibili.com/bangumi/play/ep\(epID)"
            ))
        }
        if let seasonID, seasonID > 0 {
            candidates.append((
                query: ["season_id": String(seasonID)],
                referer: "https://www.bilibili.com/bangumi/play/ss\(seasonID)"
            ))
        }
        guard !candidates.isEmpty else { throw BiliAPIError.missingPayload }

        var lastError: Error?
        for candidate in candidates {
            do {
                let response: BiliResponse<PgcSeasonInfo> = try await get(
                    base: baseURL,
                    path: "/pgc/view/web/season",
                    query: candidate.query,
                    referer: candidate.referer,
                    responseCachePolicy: .detail
                )
                guard response.code == 0 else {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                guard let info = response.payload else { throw BiliAPIError.missingPayload }
                return info
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BiliAPIError.missingPayload
    }

    func fetchPlayURL(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot(purpose: .playback)
        let requestedQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality ?? qn
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: Self.playURLCachePlatform(
                snapshot.playbackStreamSourcePreference.cachePlatform,
                requestedQuality: requestedQuality
            )
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled,
            credentialVersion: snapshot.playbackCredentialVersion
        )
        if let cached = await playURLCache.value(
            for: key,
            scope: scope,
            requiredQuality: requestedQuality
        ) {
            PlayerMetricsLog.logger.info(
                "playURLMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return await applyingConfiguredHistoryAccount(
                to: cached,
                playbackSnapshot: snapshot
            )
        }

        let data = try await fetchPlayURLWithPendingRequest(
            cacheKey: key,
            scope: scope,
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            source: "playURL",
            cachePlatform: snapshot.playbackStreamSourcePreference.cachePlatform,
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
            playbackSnapshot: snapshot
        )
    }

    func fetchPgcPlayURL(
        bvid: String,
        cid: Int,
        seasonID: Int?,
        epID: Int?,
        qn: Int = 112,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot(purpose: .playback)
        let requestedQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality ?? qn
        let streamSource = snapshot.playbackStreamSourcePreference
        let keys = try await fetchWBIKeys(priority: .userInitiated)
        let referer: String
        if let epID {
            referer = "https://www.bilibili.com/bangumi/play/ep\(epID)"
        } else if let seasonID {
            referer = "https://www.bilibili.com/bangumi/play/ss\(seasonID)"
        } else {
            referer = "https://www.bilibili.com/bangumi/play/"
        }
        var lastError: Error?
        var bestFallbackData: PlayURLData?
        for codecPreference in PlayURLCodecPreference.extendedPlaybackOrder(requestedQuality: requestedQuality) {
            do {
                var query = pgcPlayURLQuery(
                    bvid: bvid,
                    cid: cid,
                    seasonID: seasonID,
                    epID: epID,
                    qn: requestedQuality,
                    streamSource: streamSource,
                    codecPreference: codecPreference
                )
                query = WBISigner.sign(query, keys: keys)
                let response: BiliResponse<PgcPlayURLResult> = try await get(
                    base: baseURL,
                    path: "/pgc/player/web/v2/playurl",
                    query: query,
                    referer: referer,
                    userAgent: userAgent(for: streamSource),
                    cookieHeader: snapshot.cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: URLSessionTask.highPriority
                )
                let data = try requirePgcPlayURLData(response, requirePlayablePayload: true)
                let requestedData = try requireRequestedQualityIfNeeded(data, requestedQuality: requestedQuality)
                guard codecPreference.accepts(requestedData) else {
                    throw BiliAPIError.emptyPlayURL
                }
                if Self.shouldContinueCodecFallback(
                    for: requestedData,
                    requestedQuality: requestedQuality,
                    requestedCodecFamily: codecPreference.selectionCodecFamily,
                    allowsUnavailableQualityFallback: codecPreference.allowsUnavailableQualityFallback
                ) {
                    bestFallbackData = preferredStartupCandidate(
                        bestFallbackData,
                        requestedData,
                        requestedQuality: requestedQuality
                    )
                    continue
                }
                return await applyingConfiguredHistoryAccount(
                    to: requestedData,
                    playbackSnapshot: snapshot
                )
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard shouldTryAlternatePlayURLCodec(after: error) else { break }
            }
        }
        if let bestFallbackData {
            return await applyingConfiguredHistoryAccount(
                to: bestFallbackData,
                playbackSnapshot: snapshot
            )
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    func clearCachedPlayURLFailures(bvid: String) async {
        await state.clearPlayURLFailuresAndTasks(containing: bvid)
    }

    func clearPlaybackPerformanceTestState(bvid: String) async {
        await state.clearPlayURLFailuresAndTasks(containing: bvid)
        await state.clearVideoDetailTasks(containing: bvid)
    }

    func cachedPlayablePlayURLFallback(bvid: String, cid: Int) async -> PlayURLData? {
        let snapshot = await requestSnapshot(purpose: .playback)
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: snapshot.isLoggedIn,
            userMID: snapshot.currentUserMID,
            guestModeEnabled: snapshot.guestModeEnabled,
            credentialVersion: snapshot.playbackCredentialVersion
        )
        guard let data = await playURLCache.playableFallback(
            bvid: bvid,
            cid: cid,
            platform: nil,
            scope: scope
        ) else { return nil }
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackSnapshot: snapshot
        )
    }

    private func applyingConfiguredHistoryAccount(
        to data: PlayURLData,
        playbackSnapshot: RequestSnapshot
    ) async -> PlayURLData {
        let historySnapshot = await requestSnapshot(purpose: .historyRead)
        guard historySnapshot.currentUserMID == playbackSnapshot.currentUserMID else {
            return data.removingHistoryMetadata()
        }
        return data
    }

    private func fetchPlayURLUncached(
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
        let requestedQuality = preferredQuality
            ?? snapshot.effectivePreferredVideoQuality
            ?? qn
        let streamSource = snapshot.playbackStreamSourcePreference
        let initialCodecPreference = PlayURLCodecPreference.primaryPlaybackOrder(
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
            logPreferredQualityMiss(stage: "wbiPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
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
                        cookieModePrefix: "auth-wbi-webQualityProbe-\(PlaybackStreamSourcePreference.web.cachePlatform)",
                        credentialVersion: snapshot.playbackCredentialVersion,
                        streamSource: .web,
                        priority: .userInitiated
                    )
                }
                logPlayURLStage("wbiWebQualityProbe", bvid: bvid, cid: cid, start: webQualityProbeStart, data: playable)
                if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                    logPlayURLStage("completeWBIWebQualityProbe", bvid: bvid, cid: cid, start: requestStart, data: playable)
                    return playable
                }
                logPreferredQualityMiss(stage: "wbiWebQualityProbe", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
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
            logPreferredQualityMiss(stage: "legacyPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
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
            logPlayURLStage("legacyAnonymousFallback", bvid: bvid, cid: cid, start: legacyAnonymousStageStart, data: playableFallback)
            if let existing = bestPlayableData {
                let merged = existing.mergingPlayableStreams(from: playableFallback)
                if merged.highestPlayableQuality > existing.highestPlayableQuality
                    || playableFallback.durl?.isEmpty == false {
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
                logPlayURLStage("completeBestFallback", bvid: bvid, cid: cid, start: requestStart, data: bestPlayableData)
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
            playbackSnapshot: snapshot
        )
    }

    private func makePiliPlusWebpageHedge(
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
                let isCancellation = Task.isCancelled
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
            playbackSnapshot: snapshot
        )
    }

    private func fetchPiliPlusStyleStartupFallbackPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        webpageHedge: PiliPlusWebpageHedge? = nil
    ) async throws -> PlayURLData {
        _ = cid
        let webpageHedge = webpageHedge ?? makePiliPlusWebpageHedge(
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
                playbackSnapshot: snapshot
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
            playbackSnapshot: snapshot
        )
    }

    private func fetchPlayURLWithPendingRequest(
        cacheKey: PlayURLCacheKey,
        scope: PlayURLCacheLoginScope,
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        source: String,
        cachePlatform: String,
        isStartup: Bool,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        let pendingKey = PendingPlayURLRequestKey(cacheKey: cacheKey, scope: scope)
        if let existingRequest = await state.pendingPlayURLRequest(for: pendingKey) {
            PlayerMetricsLog.logger.info(
                "playURLRequestJoined source=\(source, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return try await Self.awaitSharedTask(existingRequest.task)
        }

        let requestID = UUID()
        let startGate = PendingPlayURLRequestStartGate()
        let task = Task<PlayURLData, Error>(priority: .userInitiated) {
            await startGate.wait()
            do {
                try Task.checkCancellation()
                let data = try await operation()
                let storageKey: PlayURLCacheKey
                if data.hasPlayableMediaQuality(requestedQuality) {
                    storageKey = cacheKey
                } else if let actualQuality = Self.startupCandidateQuality(
                    in: data,
                    requestedQuality: requestedQuality
                ), actualQuality < requestedQuality {
                    if isStartup,
                       PiliPlusStylePlayURLSelectionExperiment.stored(),
                       Self.canUseUnavailablePreferredStartupFallback(
                           data,
                           requestedQuality: requestedQuality,
                           isAuthoritativeSource: true
                       ) {
                        storageKey = cacheKey
                    } else {
                        storageKey = PlayURLCacheKey(
                            bvid: bvid,
                            cid: cid,
                            requestedQuality: actualQuality,
                            audioLanguage: cacheKey.audioLanguage,
                            fnval: cacheKey.fnval,
                            fnver: cacheKey.fnver,
                            platform: Self.playURLCachePlatform(
                                cachePlatform,
                                requestedQuality: actualQuality,
                                isStartup: isStartup
                            )
                        )
                    }
                } else {
                    storageKey = cacheKey
                }
                await self.playURLCache.store(data, for: storageKey, scope: scope)
                await self.state.clearPendingPlayURLRequest(for: pendingKey, id: requestID)
                return data
            } catch {
                await self.state.clearPendingPlayURLRequest(for: pendingKey, id: requestID)
                throw error
            }
        }
        let request = PendingPlayURLRequest(id: requestID, task: task)
        if let existingRequest = await state.insertPendingPlayURLRequestIfAbsent(request, for: pendingKey) {
            task.cancel()
            await startGate.open()
            PlayerMetricsLog.logger.info(
                "playURLRequestJoinedAfterRace source=\(source, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return try await Self.awaitSharedTask(existingRequest.task)
        }

        await startGate.open()
        return try await Self.awaitSharedTask(task)
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

    func hasCachedStartupPlayURL(
        bvid: String,
        cid: Int,
        preferredQuality: Int? = nil
    ) async -> Bool {
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
        return await playURLCache.contains(
            key,
            scope: scope,
            requiredQuality: requestedQuality,
            allowsVerifiedLowerQualityFallback: PiliPlusStylePlayURLSelectionExperiment.stored()
        )
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


    private func fetchPiliPlusStyleStartupPlayURL(
        bvid: String,
        cid: Int,
        requestedQuality: Int
    ) async throws -> PlayURLData {
        let snapshot = await requestSnapshot(purpose: .playback)
        let routeHintKey = Self.startupWBIRouteHintKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            snapshot: snapshot
        )
        let routeHint = await state.startupWBIRouteHint(for: routeHintKey)
        let queryQuality = Self.piliPlusPrimaryProbeQuality(
            requestedQuality: requestedQuality
        )
        let stageStart = CACurrentMediaTime()
        var keysElapsed: Double?
        var baseAttempt: PiliPlusWBIQualityAttempt?
        var rescueAttempt: PiliPlusWBIQualityAttempt?

        do {
            let keysStart = CACurrentMediaTime()
            let keys = try await fetchWBIKeys(priority: .userInitiated)
            keysElapsed = PlayerMetricsLog.elapsedMilliseconds(since: keysStart)
            let initialAttempt = await fetchPiliPlusWBIQualityAttempt(
                bvid: bvid,
                cid: cid,
                queryQuality: queryQuality,
                requestedQuality: requestedQuality,
                keys: keys,
                snapshot: snapshot
            )
            baseAttempt = initialAttempt
            var selectedAttempt = initialAttempt
            if !initialAttempt.isSuccessful,
               let error = initialAttempt.error,
               Self.shouldRescuePiliPlusWBI(after: error),
               let rescueQuality = Self.piliPlusCompatibilityRescueProbeQuality(
                requestedQuality: requestedQuality,
                baseQuality: queryQuality
               ) {
                let attemptedRescue = await fetchPiliPlusWBIQualityAttempt(
                    bvid: bvid,
                    cid: cid,
                    queryQuality: rescueQuality,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    snapshot: snapshot
                )
                rescueAttempt = attemptedRescue
                if attemptedRescue.isSuccessful {
                    selectedAttempt = attemptedRescue
                }
            }
            guard selectedAttempt.isSuccessful,
                  let data = selectedAttempt.data,
                  let selectedQuality = selectedAttempt.selectedQuality
            else {
                let finalError = rescueAttempt?.error
                    ?? initialAttempt.error
                    ?? BiliAPIError.emptyPlayURL
                if Self.shouldRescuePiliPlusWBI(after: finalError) {
                    await state.storeStartupWBIRouteHint(.webpageOnly, for: routeHintKey)
                }
                throw finalError
            }

            try Task.checkCancellation()
            recordPiliPlusStylePlayURLDiagnostic(
                bvid: bvid,
                result: "success",
                requestedQuality: requestedQuality,
                queryQuality: queryQuality,
                selectedQuality: selectedQuality,
                requests: rescueAttempt == nil ? 1 : 2,
                keysElapsedMilliseconds: keysElapsed,
                requestElapsedMilliseconds: initialAttempt.elapsedMilliseconds,
                selectionElapsedMilliseconds: selectedAttempt.selectionElapsedMilliseconds,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: stageStart),
                routeHint: routeHint,
                availabilityData: data,
                targetResponseDiagnostic: initialAttempt.responseDiagnostic,
                rescueQueryQuality: rescueAttempt?.queryQuality,
                rescueRequestElapsedMilliseconds: rescueAttempt?.elapsedMilliseconds,
                rescueResponseDiagnostic: rescueAttempt?.responseDiagnostic
            )
            PlayerMetricsLog.logger.info(
                "piliPlusStyleStartupSelection bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) requested=\(requestedQuality, privacy: .public) query=\(queryQuality, privacy: .public) selected=\(selectedQuality, privacy: .public) requests=1 codec=automatic"
            )
            return data
        } catch {
            guard !Task.isCancelled else { throw error }
            recordPiliPlusStylePlayURLDiagnostic(
                bvid: bvid,
                result: "failure",
                requestedQuality: requestedQuality,
                queryQuality: queryQuality,
                selectedQuality: (rescueAttempt ?? baseAttempt)?.data.flatMap {
                    Self.startupCandidateQuality(in: $0, requestedQuality: requestedQuality)
                },
                requests: rescueAttempt == nil ? 1 : 2,
                keysElapsedMilliseconds: keysElapsed,
                requestElapsedMilliseconds: baseAttempt?.elapsedMilliseconds,
                selectionElapsedMilliseconds: (rescueAttempt ?? baseAttempt)?.selectionElapsedMilliseconds,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: stageStart),
                routeHint: routeHint,
                availabilityData: (rescueAttempt ?? baseAttempt)?.data,
                targetResponseDiagnostic: baseAttempt?.responseDiagnostic,
                rescueQueryQuality: rescueAttempt?.queryQuality,
                rescueRequestElapsedMilliseconds: rescueAttempt?.elapsedMilliseconds,
                rescueResponseDiagnostic: rescueAttempt?.responseDiagnostic,
                error: error
            )
            throw error
        }
    }

    private func fetchPiliPlusWBIQualityAttempt(
        bvid: String,
        cid: Int,
        queryQuality: Int,
        requestedQuality: Int,
        keys: WBIKeys,
        snapshot: RequestSnapshot
    ) async -> PiliPlusWBIQualityAttempt {
        let requestStart = CACurrentMediaTime()
        var diagnosticData: PlayURLData?
        var selectionElapsed: Double?
        var responseDiagnostic: String?

        do {
            let requestTask = Task<BiliResponse<PlayURLData>, Error>(priority: .userInitiated) { [self] in
                let query = Self.piliPlusStylePlayURLQuery(
                    bvid: bvid,
                    cid: cid,
                    qn: queryQuality,
                    tryLook: !snapshot.isLoggedIn
                )
                return try await get(
                    base: baseURL,
                    path: "/x/player/wbi/playurl",
                    query: WBISigner.sign(query, keys: keys),
                    referer: "https://www.bilibili.com/video/\(bvid)",
                    userAgent: userAgent(for: .web),
                    cookieHeader: snapshot.cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: .userInitiated
                )
            }
            defer { requestTask.cancel() }
            let response = try await Self.awaitSharedTask(requestTask)
            responseDiagnostic = Self.piliPlusWBIResponseDiagnosticMessage(
                queryQuality: queryQuality,
                response: response,
                isLoggedIn: snapshot.isLoggedIn,
                hasSESSDATA: Self.cookieValue(named: "SESSDATA", in: snapshot.cookieHeader) != nil,
                hasDedeUserID: Self.cookieValue(named: "DedeUserID", in: snapshot.cookieHeader) != nil,
                hasAccessKey: snapshot.appAccessKey?.isEmpty == false,
                accountPurposeEnabled: snapshot.isAccountPurposeEnabled
            )
            diagnosticData = response.payload
            let data = try requirePlayURLData(response, requirePlayablePayload: true)
            diagnosticData = data
            let selectionStart = CACurrentMediaTime()
            let selectedQuality = Self.startupCandidateQuality(
                in: data,
                requestedQuality: requestedQuality
            )
            selectionElapsed = PlayerMetricsLog.elapsedMilliseconds(since: selectionStart)
            guard let selectedQuality else {
                throw TargetQualityUnavailableError(
                    requestedQuality: requestedQuality,
                    fallbackQuality: nil,
                    fallbackData: data
                )
            }
            guard Self.canUsePiliPlusCompatibilityResponse(
                data,
                requestedQuality: requestedQuality
            ) else {
                throw TargetQualityUnavailableError(
                    requestedQuality: requestedQuality,
                    fallbackQuality: selectedQuality,
                    fallbackData: data
                )
            }
            return PiliPlusWBIQualityAttempt(
                queryQuality: queryQuality,
                selectedQuality: selectedQuality,
                data: data,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                selectionElapsedMilliseconds: selectionElapsed,
                responseDiagnostic: responseDiagnostic,
                error: nil
            )
        } catch {
            return PiliPlusWBIQualityAttempt(
                queryQuality: queryQuality,
                selectedQuality: nil,
                data: diagnosticData,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                selectionElapsedMilliseconds: selectionElapsed,
                responseDiagnostic: responseDiagnostic,
                error: error
            )
        }
    }

    nonisolated static func piliPlusWBIResponseDiagnosticMessage(
        queryQuality: Int,
        response: BiliResponse<PlayURLData>,
        isLoggedIn: Bool,
        hasSESSDATA: Bool,
        hasDedeUserID: Bool,
        hasAccessKey: Bool,
        accountPurposeEnabled: Bool
    ) -> String {
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }

        let payload = response.payload
        return [
            "q\(queryQuality)",
            "outer\(response.code)",
            "inner\(payload?.code.map(String.init) ?? "-")",
            "payload\(bit(payload != nil))",
            "dashV\(payload?.dash?.video?.count ?? 0)",
            "dashA\(payload?.dash?.audio?.count ?? 0)",
            "durl\(payload?.durl?.count ?? 0)",
            "accept\(payload?.acceptQuality?.count ?? 0)",
            "support\(payload?.supportFormats?.count ?? 0)",
            "loggedIn\(bit(isLoggedIn))",
            "sess\(bit(hasSESSDATA))",
            "dede\(bit(hasDedeUserID))",
            "access\(bit(hasAccessKey))",
            "purpose\(bit(accountPurposeEnabled))"
        ].joined(separator: ":")
    }

    private nonisolated func recordPiliPlusStylePlayURLDiagnostic(
        bvid: String,
        result: String,
        requestedQuality: Int,
        queryQuality: Int,
        selectedQuality: Int?,
        requests: Int,
        keysElapsedMilliseconds: Double?,
        requestElapsedMilliseconds: Double?,
        selectionElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        routeHint: StartupWBIRouteHint?,
        availabilityData: PlayURLData? = nil,
        targetResponseDiagnostic: String? = nil,
        rescueQueryQuality: Int? = nil,
        rescueRequestElapsedMilliseconds: Double? = nil,
        rescueResponseDiagnostic: String? = nil,
        error: Error? = nil
    ) {
        let message = Self.piliPlusStylePlayURLDiagnosticMessage(
            result: result,
            requestedQuality: requestedQuality,
            queryQuality: queryQuality,
            selectedQuality: selectedQuality,
            requests: requests,
            keysElapsedMilliseconds: keysElapsedMilliseconds,
            requestElapsedMilliseconds: requestElapsedMilliseconds,
            selectionElapsedMilliseconds: selectionElapsedMilliseconds,
            totalElapsedMilliseconds: totalElapsedMilliseconds,
            routeHint: routeHint,
            availabilityData: availabilityData,
            targetResponseDiagnostic: targetResponseDiagnostic,
            rescueQueryQuality: rescueQueryQuality,
            rescueRequestElapsedMilliseconds: rescueRequestElapsedMilliseconds,
            rescueResponseDiagnostic: rescueResponseDiagnostic,
            error: error
        )
        Task { @MainActor in
            PlayerMetricsLog.record(.startupScheduler, metricsID: bvid, message: message)
        }
    }

    nonisolated static func piliPlusStylePlayURLDiagnosticMessage(
        result: String,
        requestedQuality: Int,
        queryQuality: Int? = nil,
        selectedQuality: Int?,
        requests: Int,
        keysElapsedMilliseconds: Double?,
        requestElapsedMilliseconds: Double?,
        selectionElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        routeHint: StartupWBIRouteHint? = nil,
        availabilityData: PlayURLData? = nil,
        targetResponseDiagnostic: String? = nil,
        rescueQueryQuality: Int? = nil,
        rescueRequestElapsedMilliseconds: Double? = nil,
        rescueResponseDiagnostic: String? = nil,
        error: Error? = nil
    ) -> String {
        func duration(_ milliseconds: Double?) -> String {
            guard let milliseconds else { return "-" }
            return "\(Int(milliseconds.rounded()))ms"
        }

        var parts = [
            "piliPlusStylePlayURL",
            "result=\(result)",
            "route=\(rescueQueryQuality == nil ? "baseQualityWBI" : "baseThenRescueWBI")",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "target=\(requestedQuality)",
            "queryQ=\(queryQuality ?? requestedQuality)",
            "routeHint=\(routeHint?.rawValue ?? "none")",
            "selected=\(selectedQuality.map(String.init) ?? "-")",
            "requests=\(requests)",
            "keys=\(duration(keysElapsedMilliseconds))",
            "request=\(duration(requestElapsedMilliseconds))",
            "selection=\(duration(selectionElapsedMilliseconds))",
            "total=\(duration(totalElapsedMilliseconds))"
        ]
        if let availabilityData {
            parts.append(availabilityData.targetQualityAvailabilitySummary(requestedQuality))
        }
        if let targetResponseDiagnostic {
            parts.append("baseResponse=\(targetResponseDiagnostic)")
        }
        if let rescueQueryQuality {
            parts.append("rescueQ=\(rescueQueryQuality)")
            parts.append("rescue=\(duration(rescueRequestElapsedMilliseconds))")
        }
        if let rescueResponseDiagnostic {
            parts.append("rescueResponse=\(rescueResponseDiagnostic)")
        }
        if let error {
            parts.append("reason=\(sanitizedPiliPlusStylePlayURLError(error))")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusStartupFallbackDiagnosticMessage(
        result: String,
        route: String,
        requestedQuality: Int,
        selectedQuality: Int?,
        legacyResult: String,
        legacyElapsedMilliseconds: Double?,
        standardWBIResult: String = "notStarted",
        standardWBIQuality: Int? = nil,
        standardWBIElapsedMilliseconds: Double? = nil,
        webpageElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        legacyError: Error? = nil,
        standardWBIError: Error? = nil,
        webpageError: Error? = nil
    ) -> String {
        func duration(_ milliseconds: Double?) -> String {
            guard let milliseconds else { return "-" }
            return "\(Int(milliseconds.rounded()))ms"
        }

        var parts = [
            "piliPlusFallback",
            "result=\(result)",
            "route=\(route)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "target=\(requestedQuality)",
            "selected=\(selectedQuality.map(String.init) ?? "-")",
            "legacyResult=\(legacyResult)",
            "legacy=\(duration(legacyElapsedMilliseconds))",
            "wbiResult=\(standardWBIResult)",
            "wbiQ=\(standardWBIQuality.map(String.init) ?? "-")",
            "wbi=\(duration(standardWBIElapsedMilliseconds))",
            "webpage=\(duration(webpageElapsedMilliseconds))",
            "total=\(duration(totalElapsedMilliseconds))"
        ]
        if let legacyError {
            parts.append("legacyReason=\(sanitizedPiliPlusStylePlayURLError(legacyError))")
        }
        if let standardWBIError {
            parts.append("wbiReason=\(sanitizedPiliPlusStylePlayURLError(standardWBIError))")
        }
        if let webpageError {
            parts.append("webpageReason=\(sanitizedPiliPlusStylePlayURLError(webpageError))")
        }
        return parts.joined(separator: " ")
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
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms"
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
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms"
        ]
        if let expectedBytes, expectedBytes > Int64(receivedBytes) {
            parts.append("saved=\(expectedBytes - Int64(receivedBytes))")
        }
        if let fallbackReason {
            parts.append("fallbackReason=\(fallbackReason)")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusPrimaryProbeQuality(requestedQuality: Int) -> Int {
        requestedQuality == 116 ? 112 : requestedQuality
    }

    nonisolated static func piliPlusCompatibilityRescueProbeQuality(
        requestedQuality: Int,
        baseQuality: Int
    ) -> Int? {
        guard requestedQuality > 80, baseQuality > 80 else { return nil }
        return 80
    }

    nonisolated static func shouldRescuePiliPlusWBI(after error: Error) -> Bool {
        if error is TargetQualityUnavailableError {
            return true
        }
        guard let apiError = error as? BiliAPIError else { return false }
        if case .emptyPlayURL = apiError {
            return true
        }
        return false
    }

    nonisolated static func sanitizedPiliPlusStylePlayURLError(_ error: Error) -> String {
        if error is TargetQualityUnavailableError {
            return "targetQualityUnavailable"
        }
        if let error = error as? BiliAPIError {
            switch error {
            case .invalidURL: return "invalidURL"
            case .emptyData: return "emptyData"
            case .api(let code, _): return "api\(code)"
            case .missingPayload: return "missingPayload"
            case .missingSESSDATA: return "missingSESSDATA"
            case .missingCSRF: return "missingCSRF"
            case .emptyPlayURL: return "emptyPlayURL"
            case .unsupportedHardwarePlayback: return "unsupportedHardwarePlayback"
            }
        }
        if let error = error as? URLError {
            return "url\(error.errorCode)"
        }
        return String(describing: type(of: error))
            .replacingOccurrences(of: " ", with: "_")
    }

    private nonisolated func startupRequestedQuality(configuredQuality: Int?) -> Int {
        configuredQuality ?? LibraryStore.defaultPreferredVideoQuality
    }

    private nonisolated static func startupWBIRouteHintKey(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        snapshot: RequestSnapshot
    ) -> StartupWBIRouteHintKey {
        StartupWBIRouteHintKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            accountMID: snapshot.currentUserMID,
            credentialVersion: snapshot.playbackCredentialVersion
        )
    }

    private func fetchRacedStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        requestLease: StartupPlayURLRequestLease?,
        requestSource: StartupPlayURLRequestSource
    ) async throws -> StartupPlayURLRaceResult? {
        let raceStart = CACurrentMediaTime()
        let suppressionStatus = await startupWBISuppressionStatus()
        let piliPlusStyleEnabled = PiliPlusStylePlayURLSelectionExperiment.stored()
        let routeHint: StartupWBIRouteHint?
        if piliPlusStyleEnabled {
            let snapshot = await requestSnapshot(purpose: .playback)
            routeHint = await state.startupWBIRouteHint(
                for: Self.startupWBIRouteHintKey(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    snapshot: snapshot
                )
            )
        } else {
            routeHint = nil
        }
        let shouldRaceWBI = suppressionStatus == nil && routeHint != .webpageOnly
        let playbackEnvironment = PlaybackEnvironment.current
        let startupGrace = playbackEnvironment.preferredPlayURLStartupGrace
        let schedulingDecision = await StartupPlayURLRoutePerformanceStore.shared.decision(
            networkClass: playbackEnvironment.networkClass,
            wbiAvailable: shouldRaceWBI
        ).preferringWBIForPiliPlus(
            piliPlusStyleEnabled: piliPlusStyleEnabled,
            wbiAvailable: shouldRaceWBI
        )
        let defersWebpageFallbackUntilWBIFailure = schedulingDecision
            .defersWebpageFallbackUntilWBIFailure(
                piliPlusStyleEnabled: piliPlusStyleEnabled
            )
        let schedulerBaseMessage = shouldRaceWBI
            ? schedulingDecision.diagnosticMessage(
                piliPlusStyleEnabled: piliPlusStyleEnabled
            )
            : startupWBISuppressionMessage(
                mode: "adaptive",
                suppressionStatus: suppressionStatus,
                routeHint: routeHint
            )
        let schedulerMessage = piliPlusStyleEnabled
            ? "\(schedulerBaseMessage) strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey) routeHint=\(routeHint?.rawValue ?? "none")"
            : schedulerBaseMessage
        if recordsStartupSchedulerFeedback(
            requestSource: requestSource,
            requestLease: requestLease
        ) {
            await recordStartupSchedulerMessage(schedulerMessage, bvid: bvid)
        }
        var bestStartupResult: StartupPlayURLRaceResult?
        var lastError: Error?
        let fallbackTracker = schedulingDecision.usesStaggeredFallback
            ? StartupPlayURLFallbackTracker(
                initialStatus: defersWebpageFallbackUntilWBIFailure ? .deferred : .waiting
            )
            : nil
        let webpageHedge = defersWebpageFallbackUntilWBIFailure
            ? makePiliPlusWebpageHedge(
                bvid: bvid,
                page: page,
                delayNanoseconds: PiliPlusStylePlayURLSelectionExperiment.webpageHedgeDelayNanoseconds
            )
            : nil
        defer { webpageHedge?.task.cancel() }

        return await withTaskGroup(of: StartupPlayURLAttempt.self, returning: StartupPlayURLRaceResult?.self) { group in
            if schedulingDecision.usesStaggeredFallback,
               let primaryRoute = schedulingDecision.primaryRoute,
               let fallbackRoute = schedulingDecision.fallbackRoute {
                group.addTask(priority: .userInitiated) {
                    await self.startupPlayURLAttempt(
                        route: primaryRoute,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality
                    )
                }
                if !defersWebpageFallbackUntilWBIFailure {
                    group.addTask(priority: .utility) {
                        do {
                            try await Task.sleep(
                                nanoseconds: PlaybackStartupRequestSchedulingPolicy.staggeredFallbackDelayNanoseconds
                            )
                        } catch {
                            await fallbackTracker?.markCancelledBeforeStart()
                            return StartupPlayURLAttempt(
                                stage: "startupFallbackCancelled",
                                route: nil,
                                elapsedMilliseconds: nil,
                                data: nil,
                                error: nil,
                                isAuthoritativePlayURLSource: false
                            )
                        }
                        guard !Task.isCancelled else {
                            await fallbackTracker?.markCancelledBeforeStart()
                            return StartupPlayURLAttempt(
                                stage: "startupFallbackCancelled",
                                route: nil,
                                elapsedMilliseconds: nil,
                                data: nil,
                                error: nil,
                                isAuthoritativePlayURLSource: false
                            )
                        }
                        await fallbackTracker?.markStarted()
                        return await self.startupPlayURLAttempt(
                            route: fallbackRoute,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality
                        )
                    }
                }
            } else {
                if startupGrace > 0 {
                    group.addTask(priority: .userInitiated) {
                        try? await Task.sleep(nanoseconds: startupGrace)
                        return StartupPlayURLAttempt(
                            stage: "startupRaceTimeout",
                            route: nil,
                            elapsedMilliseconds: nil,
                            data: nil,
                            error: nil,
                            isAuthoritativePlayURLSource: false
                        )
                    }
                }

                group.addTask(priority: .userInitiated) {
                    await self.startupPlayURLAttempt(
                        route: .webpage,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality
                    )
                }

                if shouldRaceWBI {
                    group.addTask(priority: .userInitiated) {
                        await self.startupPlayURLAttempt(
                            route: .wbi,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality
                        )
                    }
                }
            }

            while let attempt = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return nil
                }

                if attempt.stage == "startupRaceTimeout" {
                    logPlayURLStage(
                        "startupRaceGraceExpired",
                        bvid: bvid,
                        cid: cid,
                        start: raceStart
                    )
                    continue
                }
                if attempt.stage == "startupFallbackCancelled" {
                    continue
                }

                var shouldStartDeferredWebpageFallback = false
                if let data = attempt.data {
                    let result = StartupPlayURLRaceResult(
                        data: data,
                        isVerifiedUnavailablePreferredFallback: Self.canUseUnavailablePreferredStartupFallback(
                            data,
                            requestedQuality: requestedQuality,
                            isAuthoritativeSource: attempt.isAuthoritativePlayURLSource
                        )
                    )
                    let hasRequestedMedia = data.hasPlayableMediaQuality(requestedQuality)
                    let acceptsRequestedQuality = hasRequestedMedia
                        || result.isVerifiedUnavailablePreferredFallback
                    if recordsStartupSchedulerFeedback(
                        requestSource: requestSource,
                        requestLease: requestLease
                    ) {
                        await recordStartupRouteAttempt(
                            attempt,
                            accepted: acceptsRequestedQuality,
                            networkClass: playbackEnvironment.networkClass,
                            requestLease: requestLease
                        )
                        if attempt.route == .wbi {
                            await recordStartupWBISuccess(bvid: bvid)
                        }
                    }
                    bestStartupResult = preferredStartupRaceCandidate(
                        bestStartupResult,
                        result,
                        requestedQuality: requestedQuality
                    )
                    if hasRequestedMedia {
                        if defersWebpageFallbackUntilWBIFailure, attempt.route == .wbi {
                            await fallbackTracker?.markNotNeeded()
                            webpageHedge?.task.cancel()
                        }
                        group.cancelAll()
                        await group.waitForAll()
                        if recordsStartupSchedulerFeedback(
                            requestSource: requestSource,
                            requestLease: requestLease
                        ) {
                            let fallbackStatus = await startupFallbackStatus(
                                tracker: fallbackTracker,
                                route: schedulingDecision.fallbackRoute
                            )
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "winner",
                                requestedQuality: requestedQuality,
                                bvid: bvid,
                                fallbackStatus: fallbackStatus
                            )
                        } else if requestSource.recordsSchedulerFeedback {
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "ignoredLate",
                                requestedQuality: requestedQuality,
                                bvid: bvid
                            )
                        }
                        logPlayURLStage(
                            "startupRaceWinner.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        return result
                    }
                    if result.isVerifiedUnavailablePreferredFallback {
                        if defersWebpageFallbackUntilWBIFailure, attempt.route == .wbi {
                            await fallbackTracker?.markNotNeeded()
                            webpageHedge?.task.cancel()
                        }
                        group.cancelAll()
                        await group.waitForAll()
                        if recordsStartupSchedulerFeedback(
                            requestSource: requestSource,
                            requestLease: requestLease
                        ) {
                            let fallbackStatus = await startupFallbackStatus(
                                tracker: fallbackTracker,
                                route: schedulingDecision.fallbackRoute
                            )
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "unavailablePreferred",
                                requestedQuality: requestedQuality,
                                bvid: bvid,
                                fallbackStatus: fallbackStatus
                            )
                        } else if requestSource.recordsSchedulerFeedback {
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "ignoredLate",
                                requestedQuality: requestedQuality,
                                bvid: bvid
                            )
                        }
                        logPlayURLStage(
                            "startupRaceUnavailablePreferredFallback.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        return result
                    }
                    logPreferredQualityMiss(
                        stage: attempt.stage,
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality,
                        data: data
                    )
                    shouldStartDeferredWebpageFallback = attempt.route == .wbi
                }

                if let error = attempt.error {
                    if recordsStartupSchedulerFeedback(
                        requestSource: requestSource,
                        requestLease: requestLease
                    ) {
                        let fallbackStatus = await startupFallbackStatus(
                            tracker: fallbackTracker,
                            route: schedulingDecision.fallbackRoute
                        )
                        await recordStartupSchedulerResult(
                            attempt,
                            result: "failed",
                            requestedQuality: requestedQuality,
                            bvid: bvid,
                            fallbackStatus: fallbackStatus
                        )
                        if !(error is CancellationError),
                           (error as? URLError)?.code != .cancelled {
                            await recordStartupRouteAttempt(
                                attempt,
                                accepted: false,
                                networkClass: playbackEnvironment.networkClass,
                                requestLease: requestLease
                            )
                        }
                        if attempt.stage == "startupWBI" {
                            await recordStartupWBIFailureIfNeeded(error, bvid: bvid)
                        }
                    } else if requestSource.recordsSchedulerFeedback {
                        await recordStartupSchedulerResult(
                            attempt,
                            result: "ignoredLate",
                            requestedQuality: requestedQuality,
                            bvid: bvid
                        )
                    }
                    lastError = error
                    logPlayURLStage(
                        "\(attempt.stage)Fallback",
                        bvid: bvid,
                        cid: cid,
                        start: raceStart,
                        error: error
                    )
                    shouldStartDeferredWebpageFallback = attempt.route == .wbi
                }

                if defersWebpageFallbackUntilWBIFailure,
                   shouldStartDeferredWebpageFallback,
                   let fallbackRoute = schedulingDecision.fallbackRoute {
                    await fallbackTracker?.markStartedAfterWBIFailure()
                    group.addTask(priority: .userInitiated) {
                        await self.startupPlayURLAttempt(
                            route: fallbackRoute,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality,
                            webpageHedge: webpageHedge
                        )
                    }
                }
            }

            if let bestStartupResult {
                logPlayURLStage(
                    "startupRaceBestFallback",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    data: bestStartupResult.data
                )
            } else if let lastError {
                logPlayURLStage(
                    "startupRaceFailed",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    error: lastError
                )
            }
            return bestStartupResult
        }
    }

    private func startupPlayURLAttempt(
        route: StartupPlayURLRoute,
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        webpageHedge: PiliPlusWebpageHedge? = nil
    ) async -> StartupPlayURLAttempt {
        let start = CACurrentMediaTime()
        let stage = route == .wbi ? "startupWBI" : "startupWebpage"
        // Both routes use the current playback account's cookies, so either can
        // authoritatively declare that the requested quality is unavailable.
        let isAuthoritativePlayURLSource = true
        do {
            let data: PlayURLData
            switch route {
            case .webpage:
                if PiliPlusStylePlayURLSelectionExperiment.stored() {
                    data = try await fetchPiliPlusStyleStartupFallbackPlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality,
                        webpageHedge: webpageHedge
                    )
                } else {
                    data = try await fetchWebPagePlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        preferredQuality: requestedQuality
                    )
                }
            case .wbi:
                if PiliPlusStylePlayURLSelectionExperiment.stored() {
                    data = try await fetchPiliPlusStyleStartupPlayURL(
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality
                    )
                } else {
                    let keys = try await fetchWBIKeys(priority: .userInitiated)
                    data = try await fetchWBIStartupPlayURL(
                        bvid: bvid,
                        cid: cid,
                        keys: keys,
                        preferredQuality: requestedQuality
                    )
                }
            }
            return StartupPlayURLAttempt(
                stage: stage,
                route: route,
                elapsedMilliseconds: max(Int(PlayerMetricsLog.elapsedMilliseconds(since: start).rounded()), 1),
                data: data,
                error: nil,
                isAuthoritativePlayURLSource: isAuthoritativePlayURLSource
            )
        } catch {
            return StartupPlayURLAttempt(
                stage: stage,
                route: route,
                elapsedMilliseconds: max(Int(PlayerMetricsLog.elapsedMilliseconds(since: start).rounded()), 1),
                data: nil,
                error: error,
                isAuthoritativePlayURLSource: isAuthoritativePlayURLSource
            )
        }
    }

    private func recordStartupRouteAttempt(
        _ attempt: StartupPlayURLAttempt,
        accepted: Bool,
        networkClass: PlaybackEnvironment.NetworkClass,
        requestLease: StartupPlayURLRequestLease?
    ) async {
        guard let route = attempt.route,
              let elapsedMilliseconds = attempt.elapsedMilliseconds
        else { return }
        _ = await StartupPlayURLRoutePerformanceStore.shared.record(
            route: route,
            networkClass: networkClass,
            elapsedMilliseconds: elapsedMilliseconds,
            accepted: accepted,
            requestLease: requestLease
        )
    }

    private nonisolated func recordsStartupSchedulerFeedback(
        requestSource: StartupPlayURLRequestSource,
        requestLease: StartupPlayURLRequestLease?
    ) -> Bool {
        requestSource.recordsSchedulerFeedback
            && StartupPlayURLFeedbackEligibility.allows(requestLease)
    }

    private nonisolated func startupWBISuppressionMessage(
        mode: String,
        suppressionStatus: StartupWBISuppressionStatus?,
        routeHint: StartupWBIRouteHint? = nil
    ) -> String {
        if routeHint == .webpageOnly {
            return "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=routeHint reason=emptyPlayURL remaining=short"
        }
        guard let suppressionStatus else {
            return "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=foreground reason=unknown remaining=-"
        }
        return "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=foreground reason=\(suppressionStatus.reason) remaining=\(suppressionStatus.remainingMilliseconds)ms"
    }

    private func recordStartupWBISuccess(bvid: String) async {
        guard await state.recordStartupWBISuccess() else { return }
        await recordStartupSchedulerMessage(
            "startupWBIHealth source=foreground result=success action=reset",
            bvid: bvid
        )
    }

    private func recordStartupWBIFailureIfNeeded(_ error: Error, bvid: String) async {
        guard let reason = Self.startupWBIHealthFailureReason(for: error) else { return }
        let update = await state.recordStartupWBIFailure(reason: reason)
        switch update {
        case .observed(let consecutiveFailures):
            await recordStartupSchedulerMessage(
                "startupWBIHealth source=foreground result=failure reason=\(reason) failures=\(consecutiveFailures)/\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold) action=observe",
                bvid: bvid
            )
        case .suppressed(let status):
            await recordStartupSchedulerMessage(
                "startupWBIHealth source=foreground result=failure reason=\(status.reason) failures=\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold)/\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold) action=suppress remaining=\(status.remainingMilliseconds)ms",
                bvid: bvid
            )
        }
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

    private func recordStartupSchedulerMessage(_ message: String, bvid: String) async {
        await MainActor.run {
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: bvid,
                message: message
            )
        }
    }

    private func recordStartupSchedulerResult(
        _ attempt: StartupPlayURLAttempt,
        result: String,
        requestedQuality: Int,
        bvid: String,
        fallbackStatus: String? = nil
    ) async {
        guard let route = attempt.route else { return }
        let elapsed = attempt.elapsedMilliseconds.map { "\($0)ms" } ?? "-"
        let fallback = fallbackStatus.map { " fallback=\($0)" } ?? ""
        await recordStartupSchedulerMessage(
            "startupSchedulerResult result=\(result) route=\(route.rawValue) elapsed=\(elapsed) requestedQ=\(requestedQuality)\(fallback)",
            bvid: bvid
        )
    }

    private func startupFallbackStatus(
        tracker: StartupPlayURLFallbackTracker?,
        route: StartupPlayURLRoute?
    ) async -> String {
        guard let route else { return "notScheduled" }
        guard let tracker else { return "\(route.rawValue):unknown" }
        let status = await tracker.currentStatus()
        return "\(route.rawValue):\(status.rawValue)"
    }

    private func cancelPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String
    ) async {
        let snapshot = await requestSnapshot(purpose: .playback)
        let cacheKey = playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode,
            credentialVersion: snapshot.playbackCredentialVersion
        )
        await state.cancelPlayURLStage(cacheKey)
    }

    private nonisolated func userAgent(for streamSource: PlaybackStreamSourcePreference) -> String {
        switch streamSource {
        case .web:
            return Self.webUserAgent
        case .app:
            return Self.mobileUserAgent
        }
    }

    private func preferredStartupCandidate(
        _ lhs: PlayURLData?,
        _ rhs: PlayURLData,
        requestedQuality: Int
    ) -> PlayURLData? {
        guard Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality) != nil else {
            return lhs
        }
        guard let lhs else { return rhs }
        guard let lhsQuality = Self.startupCandidateQuality(in: lhs, requestedQuality: requestedQuality) else {
            return rhs
        }
        let rhsQuality = Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality) ?? 0
        return rhsQuality > lhsQuality ? rhs : lhs
    }

    private func preferredStartupRaceCandidate(
        _ lhs: StartupPlayURLRaceResult?,
        _ rhs: StartupPlayURLRaceResult,
        requestedQuality: Int
    ) -> StartupPlayURLRaceResult? {
        guard Self.startupCandidateQuality(in: rhs.data, requestedQuality: requestedQuality) != nil else {
            return lhs
        }
        guard let lhs else { return rhs }
        guard let lhsQuality = Self.startupCandidateQuality(in: lhs.data, requestedQuality: requestedQuality) else {
            return rhs
        }
        let rhsQuality = Self.startupCandidateQuality(in: rhs.data, requestedQuality: requestedQuality) ?? 0
        if rhsQuality != lhsQuality {
            return rhsQuality > lhsQuality ? rhs : lhs
        }
        return rhs.isVerifiedUnavailablePreferredFallback ? rhs : lhs
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
            guard let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                $0 < requestedQuality && data.advertisedQualities.contains($0)
            }) else {
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

    private nonisolated static func playURLCachePlatform(
        _ basePlatform: String,
        requestedQuality: Int?,
        isStartup: Bool = false
    ) -> String {
        let base = isStartup ? "startup-\(basePlatform)" : basePlatform
        let selectionStrategy: String
        if isStartup && PiliPlusStylePlayURLSelectionExperiment.stored() {
            selectionStrategy = PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey
        } else {
            selectionStrategy = "strictTargetQualityV1"
        }
        return "\(base)-\(selectionStrategy)-\(playURLCodecCachePolicyToken(requestedQuality: requestedQuality))"
    }

    private nonisolated static func playURLCodecCachePolicyToken(requestedQuality: Int?) -> String {
        let preference = VideoCodecPreference.stored()
        let policy: String
        if requestedQuality.map({ Self.requiresAutomaticCodecNegotiation(requestedQuality: $0) }) == true {
            policy = "hdrAutoStrictV2"
        } else if preference.codecOrder.first == .av1, PlaybackCodecPolicy.canDecodeAV1 {
            policy = "av1FirstHardwareV1"
        } else {
            policy = "hevcFirstV2"
        }
        return "codec-\(preference.rawValue)-\(policy)"
    }

    private func logPreferredQualityMiss(
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

    private func fetchWBIStartupPlayURL(
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
           shouldRetryWBIAnonymously(after: error) {
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
           shouldRetryWBIAnonymously(after: error) {
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
           shouldTryExtendedPlayURLCodecFallback(after: error) {
            let data = try await fetchWBIPlayURLWithCodecFallbacks(
                bvid: bvid,
                cid: cid,
                requestedQuality: requestedQuality,
                keys: refreshedKeys,
                referer: referer,
                cookieHeader: anonymousCookieHeader.isEmpty ? authCookieHeader : anonymousCookieHeader,
                stagePrefix: "startupWBIExtended",
                cookieModePrefix: "\(anonymousCookieHeader.isEmpty ? "auth-wbi-extended" : "anon-wbi-extended")-\(streamSource.cachePlatform)",
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

    private func startupWBISuppressionStatus() async -> StartupWBISuppressionStatus? {
        await state.startupWBISuppressionStatus()
    }

    private enum PlayURLCodecPreference: String, CaseIterable {
        case av1
        case hevc
        case automatic
        case avc

        static func primaryPlaybackOrder(requestedQuality: Int?) -> [PlayURLCodecPreference] {
            playbackOrder(for: VideoCodecPreference.stored(), requestedQuality: requestedQuality)
        }

        static func extendedPlaybackOrder(requestedQuality: Int?) -> [PlayURLCodecPreference] {
            playbackOrder(for: VideoCodecPreference.stored(), requestedQuality: requestedQuality)
        }

        private static func playbackOrder(
            for preference: VideoCodecPreference,
            requestedQuality: Int?
        ) -> [PlayURLCodecPreference] {
            if requestedQuality.map({ BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: $0) }) == true {
                return [.automatic]
            }
            let configuredOrder = preference.codecOrder.compactMap { codec -> PlayURLCodecPreference? in
                switch codec {
                case .av1:
                    return .av1
                case .hevc:
                    return .hevc
                case .h264:
                    return .avc
                case .unknown:
                    return nil
                }
            }
            guard configuredOrder.count > 1 else {
                return configuredOrder.isEmpty ? [.automatic] : configuredOrder
            }
            if configuredOrder.first == .av1 {
                // The unconstrained response most consistently exposes AV1 alongside
                // the configured fallbacks, so selection can stay local.
                return [.automatic] + configuredOrder
            }
            return configuredOrder + [.automatic]
        }

        func videoCodecid(requestedQuality: Int) -> String? {
            guard !BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: requestedQuality) else { return nil }
            switch self {
            case .av1:
                return "13"
            case .hevc:
                return "12"
            case .automatic:
                return nil
            case .avc:
                return "7"
            }
        }

        var stageSuffix: String {
            switch self {
            case .av1:
                return "AV1"
            case .hevc:
                return ""
            case .automatic:
                return "AutoCodec"
            case .avc:
                return "AVC"
            }
        }

        func accepts(_ data: PlayURLData) -> Bool {
            switch self {
            case .av1:
                return data.dash?.video?.contains(where: \.isAV1VideoCodec) == true
            case .hevc:
                return data.dash?.video?.contains(where: \.isHEVCVideoCodec) == true
            case .avc:
                return data.dash?.video?.contains(where: \.isAVCVideoCodec) == true
            case .automatic:
                return true
            }
        }

        var selectionCodecFamily: VideoCodecFamily? {
            switch self {
            case .av1:
                return .av1
            case .hevc:
                return .hevc
            case .avc:
                return .h264
            case .automatic:
                return VideoCodecPreference.stored().codecOrder.first
            }
        }

        var allowsUnavailableQualityFallback: Bool {
            self != .automatic
        }
    }

    private nonisolated static func playURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        codecPreference: PlayURLCodecPreference = .hevc,
        tryLook: Bool = true
    ) -> [String: String] {
        var query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": streamSource.playURLPlatform,
            "high_quality": "1",
            "otype": "json",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            "dm_img_list": "[]",
            "dm_img_str": Self.randomAlphaNumeric(length: 16),
            "dm_cover_img_str": Self.randomAlphaNumeric(length: 32),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#
        ]
        if tryLook {
            query["try_look"] = "1"
        }
        if let videoCodecid = codecPreference.videoCodecid(requestedQuality: qn) {
            query["video_codecid"] = videoCodecid
        }
        return query
    }

    nonisolated static func piliPlusCompatibilityPlayURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        tryLook: Bool
    ) -> [String: String] {
        playURLQuery(
            bvid: bvid,
            cid: cid,
            qn: qn,
            streamSource: streamSource,
            codecPreference: .automatic,
            tryLook: tryLook
        )
    }

    nonisolated static func piliPlusStylePlayURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        tryLook: Bool
    ) -> [String: String] {
        var query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fourk": "1",
            "fnver": "0",
            "voice_balance": "0",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            "dm_img_list": "[]",
            "dm_img_str": piliPlusDMParameter(minLength: 16, maxLength: 64),
            "dm_cover_img_str": piliPlusDMParameter(minLength: 32, maxLength: 128),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#
        ]
        if tryLook {
            query["try_look"] = "1"
        }
        return query
    }

    private nonisolated static func piliPlusDMParameter(
        minLength: Int,
        maxLength: Int
    ) -> String {
        let length = Int.random(in: minLength...maxLength)
        let bytes = (0..<length).map { _ in UInt8.random(in: 0x26...0x7e) }
        return String(Data(bytes).base64EncodedString().dropLast(2))
    }

    private func pgcPlayURLQuery(
        bvid: String,
        cid: Int,
        seasonID: Int?,
        epID: Int?,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        codecPreference: PlayURLCodecPreference = .hevc
    ) -> [String: String] {
        var query = [
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": streamSource.playURLPlatform,
            "high_quality": "1",
            "otype": "json",
            "try_look": "1",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873"
        ]
        if bvid.hasPrefix("BV") {
            query["bvid"] = bvid
        }
        if let seasonID {
            query["season_id"] = String(seasonID)
        }
        if let epID {
            query["ep_id"] = String(epID)
        }
        if let videoCodecid = codecPreference.videoCodecid(requestedQuality: qn) {
            query["video_codecid"] = videoCodecid
        }
        return query
    }

    private func fetchLegacyPlayURLWithCodecFallbacks(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        referer: String,
        cookieHeader: String,
        streamSource: PlaybackStreamSourcePreference,
        priority: Float,
        codecPreferences: [PlayURLCodecPreference]? = nil,
        allowsCodecFallbackAfterAnyError: Bool = false
    ) async throws -> PlayURLData {
        let orderedPreferences: [PlayURLCodecPreference]
        if let codecPreferences, !codecPreferences.isEmpty {
            orderedPreferences = codecPreferences
        } else {
            orderedPreferences = PlayURLCodecPreference.extendedPlaybackOrder(
                requestedQuality: requestedQuality
            )
        }
        var lastError: Error?
        var bestFallbackData: PlayURLData?

        for codecPreference in orderedPreferences {
            do {
                let query = Self.playURLQuery(
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    streamSource: streamSource,
                    codecPreference: codecPreference
                )
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/playurl",
                    query: query,
                    referer: referer,
                    userAgent: userAgent(for: streamSource),
                    cookieHeader: cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: priority
                )
                let data = try requirePlayURLData(response, requirePlayablePayload: true)
                let requestedData = try requireRequestedQualityIfNeeded(
                    data,
                    requestedQuality: requestedQuality
                )
                guard codecPreference.accepts(requestedData) else {
                    throw BiliAPIError.emptyPlayURL
                }
                if Self.shouldContinueCodecFallback(
                    for: requestedData,
                    requestedQuality: requestedQuality,
                    requestedCodecFamily: codecPreference.selectionCodecFamily,
                    allowsUnavailableQualityFallback: codecPreference.allowsUnavailableQualityFallback
                ) {
                    bestFallbackData = preferredStartupCandidate(
                        bestFallbackData,
                        requestedData,
                        requestedQuality: requestedQuality
                    )
                    continue
                }
                return requestedData
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard shouldTryAlternatePlayURLCodec(after: error) else { break }
            }
        }

        if let bestFallbackData {
            return bestFallbackData
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    private func fetchWBIPlayURLWithCodecFallbacks(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        keys: WBIKeys,
        referer: String,
        cookieHeader: String,
        stagePrefix: String,
        cookieModePrefix: String,
        credentialVersion: Int,
        streamSource: PlaybackStreamSourcePreference,
        priority: Float,
        codecPreferences: [PlayURLCodecPreference]? = nil,
        requiresRequestedQuality: Bool = true,
        tryLook: Bool = true,
        allowsCodecFallbackAfterAnyError: Bool = false
    ) async throws -> PlayURLData {
        var lastError: Error?
        var bestFallbackData: PlayURLData?
        let orderedPreferences: [PlayURLCodecPreference]
        if let codecPreferences, !codecPreferences.isEmpty {
            orderedPreferences = codecPreferences
        } else {
            orderedPreferences = PlayURLCodecPreference.extendedPlaybackOrder(
                requestedQuality: requestedQuality
            )
        }
        for codecPreference in orderedPreferences {
            let stage = "\(stagePrefix)\(codecPreference.stageSuffix)"
            do {
                let stageStart = CACurrentMediaTime()
                let data = try await runCachedPlayURLStage(
                    stage,
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    cookieMode: "\(cookieModePrefix)-\(codecPreference.rawValue)",
                    credentialVersion: credentialVersion,
                    start: stageStart
                ) { [self] in
                    let query = Self.playURLQuery(
                        bvid: bvid,
                        cid: cid,
                        qn: requestedQuality,
                        streamSource: streamSource,
                        codecPreference: codecPreference,
                        tryLook: tryLook
                    )
                    let signed = WBISigner.sign(query, keys: keys)
                    let response: BiliResponse<PlayURLData> = try await get(
                        base: baseURL,
                        path: "/x/player/wbi/playurl",
                        query: signed,
                        referer: referer,
                        userAgent: userAgent(for: streamSource),
                        cookieHeader: cookieHeader,
                        cachePolicy: .reloadIgnoringLocalCacheData,
                        priority: priority
                    )
                    let data = try requirePlayURLData(response, requirePlayablePayload: true)
                    let requestedData = requiresRequestedQuality
                        ? try requireRequestedQualityIfNeeded(data, requestedQuality: requestedQuality)
                        : data
                    guard codecPreference.accepts(requestedData) else {
                        throw BiliAPIError.emptyPlayURL
                    }
                    return requestedData
                }
                if codecPreference != .hevc {
                    logPlayURLStage(stage, bvid: bvid, cid: cid, start: CACurrentMediaTime(), data: data)
                }
                if Self.shouldContinueCodecFallback(
                    for: data,
                    requestedQuality: requestedQuality,
                    requestedCodecFamily: codecPreference.selectionCodecFamily,
                    allowsUnavailableQualityFallback: codecPreference.allowsUnavailableQualityFallback
                ) {
                    bestFallbackData = preferredStartupCandidate(
                        bestFallbackData,
                        data,
                        requestedQuality: requestedQuality
                    )
                    continue
                }
                return data
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard allowsCodecFallbackAfterAnyError
                    || shouldTryAlternatePlayURLCodec(after: error)
                else { break }
            }
        }
        if let bestFallbackData {
            return bestFallbackData
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    private func requireRequestedQualityIfNeeded(
        _ data: PlayURLData,
        requestedQuality: Int
    ) throws -> PlayURLData {
        guard Self.requiresAutomaticCodecNegotiation(requestedQuality: requestedQuality),
              !data.hasMediaPayloadQuality(requestedQuality)
        else { return data }
        throw BiliAPIError.emptyPlayURL
    }

    private func shouldTryAlternatePlayURLCodec(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func shouldRefreshWBIKeys(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func shouldRetryWBIAnonymously(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        case .api(let code, _) where code == -351:
            return true
        default:
            return false
        }
    }

    private func shouldTryExtendedPlayURLCodecFallback(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    private func runCachedPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String,
        credentialVersion: Int,
        start: CFTimeInterval,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        let cacheKey = playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode,
            credentialVersion: credentialVersion
        )
        if let cachedFailure = await state.cachedPlayURLFailure(for: cacheKey) {
            logPlayURLStage("\(stage)CachedFailure", bvid: bvid, cid: cid, start: start, error: cachedFailure)
            throw cachedFailure
        }
        if let existingTask = await state.playURLStageTask(for: cacheKey) {
            logPlayURLStage("\(stage)Joined", bvid: bvid, cid: cid, start: start)
            return try await Self.awaitSharedTask(existingTask.task)
        }

        let requestID = UUID()
        let startGate = PendingPlayURLRequestStartGate()
        let task = Task<PlayURLData, Error>(priority: .userInitiated) {
            await startGate.wait()
            try Task.checkCancellation()
            return try await operation()
        }
        let request = PendingPlayURLStageRequest(id: requestID, task: task)
        if let existingTask = await state.insertPlayURLStageTaskIfAbsent(request, for: cacheKey) {
            task.cancel()
            await startGate.open()
            logPlayURLStage("\(stage)JoinedAfterRace", bvid: bvid, cid: cid, start: start)
            return try await Self.awaitSharedTask(existingTask.task)
        }
        await startGate.open()
        Task(priority: .utility) { [self] in
            do {
                _ = try await task.value
                await state.clearPlayURLStageTask(for: cacheKey, id: requestID)
            } catch {
                await state.clearPlayURLStageTask(for: cacheKey, id: requestID)
                logPlayURLStage(stage, bvid: bvid, cid: cid, start: start, error: error)
                await state.storePlayURLFailure(error, for: cacheKey)
            }
        }
        return try await Self.awaitSharedTask(task)
    }

    private func playURLFailureCacheKey(
        stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String,
        credentialVersion: Int
    ) -> String {
        "\(stage)|\(bvid)|\(cid)|\(qn)|\(cookieMode)|credential=\(credentialVersion)"
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
        return "unavailable|\(bvid)|\(cid)|\(requestedQuality)|credential=\(snapshot.playbackCredentialVersion)|source=\(snapshot.playbackStreamSourcePreference.cachePlatform)|codec=\(codecToken)|decode=\(hardwareToken)|network=\(networkToken)"
    }

    nonisolated static func cacheablePlayURLFailure(_ error: Error) -> BiliAPIError? {
        guard !(error is CancellationError),
              let biliError = error as? BiliAPIError
        else { return nil }

        switch biliError {
        case .api(let code, _) where code == -351:
            return biliError
        default:
            return nil
        }
    }

    nonisolated static func playURLFailureTTL(for error: BiliAPIError) -> CFTimeInterval {
        switch error {
        case .api(let code, _) where code == -351:
            return 45
        case .emptyPlayURL:
            return 10
        default:
            return 6
        }
    }

    private func logPlayURLStage(
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
        let qualities = playableVariants
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
        let qualities = variants
            .filter(\.isPlayable)
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        return qualities.isEmpty ? "-" : qualities
    }

    private func fetchWebPagePlayInfo(bvid: String, page: Int?, referer: String, cookieHeader: String?) async throws -> PlayURLData {
        guard var components = URLComponents(string: "https://www.bilibili.com/video/\(bvid)/") else {
            throw BiliAPIError.invalidURL
        }
        if let page, page > 1 {
            components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await self.cookieHeader()
        }
        applyCommonHeaders(
            to: &request,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: resolvedCookieHeader
        )
        let json: String
        if PiliPlusStylePlayURLSelectionExperiment.stored() {
            let streamStart = CACurrentMediaTime()
            do {
                let result = try await BiliWebPagePlayInfoStreamingSession.shared.fetch(
                    request: request,
                    priority: .userInitiated
                )
                if let extractedJSON = result.json {
                    json = extractedJSON
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageStreamDiagnosticMessage(
                            mode: "incremental",
                            receivedBytes: result.receivedByteCount,
                            expectedBytes: result.expectedByteCount,
                            elapsedMilliseconds: Double(result.elapsedMilliseconds)
                        ),
                        bvid: bvid
                    )
                } else if let data = result.fullPageData,
                          !data.isEmpty,
                          let html = String(data: data, encoding: .utf8),
                          let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html) {
                    json = extractedJSON
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageStreamDiagnosticMessage(
                            mode: "completedPage",
                            receivedBytes: result.receivedByteCount,
                            expectedBytes: result.expectedByteCount,
                            elapsedMilliseconds: Double(result.elapsedMilliseconds)
                        ),
                        bvid: bvid
                    )
                } else if result.receivedByteCount == 0 {
                    throw BiliAPIError.emptyData
                } else {
                    throw BiliAPIError.missingPayload
                }
            } catch {
                let isCancellation = Task.isCancelled
                    || error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                if isCancellation {
                    throw error
                }
                let fallbackReason: String
                if let urlError = error as? URLError {
                    fallbackReason = "network.\(urlError.code.rawValue)"
                } else if let reason = Self.startupWBIHealthFailureReason(for: error) {
                    fallbackReason = reason
                } else {
                    fallbackReason = String(describing: type(of: error))
                }
                let (data, response) = try await data(for: request, priority: .userInitiated)
                guard !data.isEmpty else { throw BiliAPIError.emptyData }
                guard let html = String(data: data, encoding: .utf8),
                      let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html)
                else {
                    throw BiliAPIError.missingPayload
                }
                json = extractedJSON
                let expectedBytes = response.expectedContentLength > 0
                    ? response.expectedContentLength
                    : nil
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageStreamDiagnosticMessage(
                        mode: "fullPageFallback",
                        receivedBytes: data.count,
                        expectedBytes: expectedBytes,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: streamStart),
                        fallbackReason: fallbackReason
                    ),
                    bvid: bvid
                )
            }
        } else {
            let (data, _) = try await data(for: request, priority: .userInitiated)
            guard !data.isEmpty else { throw BiliAPIError.emptyData }
            guard let html = String(data: data, encoding: .utf8),
                  let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html)
            else {
                throw BiliAPIError.missingPayload
            }
            json = extractedJSON
        }

        let response: BiliResponse<PlayURLData> = try await Self.decode(Data(json.utf8), priority: .userInitiated)
        return try requirePlayURLData(response, requirePlayablePayload: true)
    }

    private func mergeDisplayFormatsIfAvailable(
        _ playableData: PlayURLData,
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String]
    ) async -> PlayURLData {
        let streamSource = await playbackStreamSourcePreference()
        guard let metadata = try? await fetchAnonymousPlayURLMetadata(
            bvid: bvid,
            cid: cid,
            referer: referer,
            query: query,
            streamSource: streamSource
        ) else {
            return playableData
        }
        return playableData.mergingDisplayFormats(from: metadata)
    }

    private func fetchAnonymousPlayURLMetadata(
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String],
        streamSource: PlaybackStreamSourcePreference
    ) async throws -> PlayURLData {
        let response: BiliResponse<PlayURLData> = try await get(
            base: baseURL,
            path: "/x/player/playurl",
            query: query,
            referer: referer,
            userAgent: userAgent(for: streamSource),
            cookieHeader: await anonymousCookieHeader(purpose: .playback),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try requirePlayURLData(response)
    }

    private static func extractWebPagePlayInfoJSON(from html: String) -> String? {
        let markers = [
            "window.__playinfo__=",
            "window.__playinfo__ =",
            "__playinfo__="
        ]
        for marker in markers {
            guard let markerRange = html.range(of: marker),
                  let json = extractBalancedJSONObject(from: html[markerRange.upperBound...])
            else { continue }
            return json
        }
        return nil
    }

    static func extractBalancedJSONObject(from source: Substring) -> String? {
        guard let start = source.firstIndex(of: "{") else { return nil }
        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < source.endIndex {
            let character = source[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(source[start...index])
                    }
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    func fetchWBIKeys(
        priority: Float = URLSessionTask.defaultPriority,
        forcesNetworkRefresh: Bool = false
    ) async throws -> WBIKeys {
        if !forcesNetworkRefresh, let keys = await freshCachedWBIKeys() {
            return keys
        }

        if !forcesNetworkRefresh, let task = await state.wbiKeysFetchTask() {
            return try await task.value
        }

        let task = Task<WBIKeys, Error>(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) { [self] in
            let response: BiliResponse<NavUserInfo> = try await get(
                base: baseURL,
                path: "/x/web-interface/nav",
                query: [:],
                cachePolicy: forcesNetworkRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
                priority: priority
            )
            guard let image = response.payload?.wbiImg else {
                if response.code != 0 {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                throw BiliAPIError.missingPayload
            }
            return WBIKeys(
                imgKey: Self.fileStem(from: image.imgURL),
                subKey: Self.fileStem(from: image.subURL)
            )
        }
        await state.setWBIKeysFetchTask(task)
        do {
            let keys = try await task.value
            await state.storeWBIKeys(keys)
            return keys
        } catch {
            await state.clearWBIKeysFetchTask()
            throw error
        }
    }

    private func freshCachedWBIKeys() async -> WBIKeys? {
        await state.freshCachedWBIKeys()
    }

    func get<T: Decodable>(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        additionalHeaders: [String: String] = [:],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        responseCachePolicy: BiliAPIResponseCachePolicy? = nil,
        priority: Float = URLSessionTask.defaultPriority,
        timeoutInterval: TimeInterval? = nil,
        responseDataObserver: (@Sendable (Data) -> Void)? = nil
    ) async throws -> T {
        var request = try await makeRequest(
            base: base,
            path: path,
            query: query,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: cachePolicy
        )
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let responseCacheKey = responseCachePolicy.flatMap { _ in Self.responseCacheKey(for: request) }
        if responseCachePolicy != nil,
           let responseCacheKey,
           let cachedData = await BiliAPIResponseMemoryCache.shared.freshData(for: responseCacheKey) {
            guard !cachedData.isEmpty else { throw BiliAPIError.emptyData }
            return try await Self.decode(cachedData, priority: priority)
        }

        if let responseCachePolicy,
           responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
           cachePolicy != .reloadIgnoringLocalCacheData,
           let responseCacheKey,
           let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
            let decoded: T = try? await Self.decode(staleData, priority: priority) {
            refreshResponseCacheInBackground(
                request,
                cacheKey: responseCacheKey,
                policy: responseCachePolicy,
                priority: priority,
                responseDataObserver: responseDataObserver
            )
            return decoded
        }

        do {
            let data = try await readData(for: request, priority: priority)
            guard !data.isEmpty else { throw BiliAPIError.emptyData }
            let decoded: T = try await Self.decode(data, priority: priority)
            if let responseCachePolicy, let responseCacheKey {
                await BiliAPIResponseMemoryCache.shared.store(
                    data,
                    for: responseCacheKey,
                    policy: responseCachePolicy
                )
            }
            responseDataObserver?(data)
            return decoded
        } catch {
            if let responseCachePolicy,
               responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
               let responseCacheKey,
               let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
               let decoded: T = try? await Self.decode(staleData, priority: priority) {
                return decoded
            }
            throw error
        }
    }

    private func refreshResponseCacheInBackground(
        _ request: URLRequest,
        cacheKey: String,
        policy: BiliAPIResponseCachePolicy,
        priority: Float,
        responseDataObserver: (@Sendable (Data) -> Void)?
    ) {
        Task(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) { [self] in
            do {
                let data = try await readData(for: request, priority: priority)
                guard !data.isEmpty else { return }
                await BiliAPIResponseMemoryCache.shared.store(data, for: cacheKey, policy: policy)
                responseDataObserver?(data)
            } catch {
                return
            }
        }
    }

    func postForm<T: Decodable>(
        base: URL,
        path: String,
        body: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        retryPolicy: BiliNetworkRetryPolicy = .api
    ) async throws -> T {
        var request = try await makeRequest(
            base: base,
            path: path,
            query: [:],
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: body)
        let (data, _) = try await data(
            for: request,
            priority: .userInitiated,
            retryPolicy: retryPolicy
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: .userInitiated)
    }

    func postSignedAPIForm<T: Decodable>(
        path: String,
        fields: [String: String],
        profile: BiliAppSigner.Profile,
        cookieHeader: String,
        additionalHeaders: [String: String]
    ) async throws -> T {
        var request = try await makeRequest(
            base: baseURL,
            path: path,
            query: [:],
            referer: "https://space.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: BiliAppSigner.sign(fields, profile: profile))
        let (data, _) = try await data(for: request, priority: .userInitiated)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: .userInitiated)
    }

    func makeRequest(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        additionalHeaders: [String: String] = [:],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await self.cookieHeader()
        }
        applyCommonHeaders(to: &request, referer: referer, userAgent: userAgent, cookieHeader: resolvedCookieHeader)
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if cachePolicy != .useProtocolCachePolicy {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        return request
    }

    func data(
        for request: URLRequest,
        priority: Float = URLSessionTask.defaultPriority,
        retryPolicy: BiliNetworkRetryPolicy = .api
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let response = try await BiliNetworkRetry.data(
            session: session,
            request: request,
            priority: priority,
            policy: retryPolicy
        )
        ResourceCacheAutoTrim.schedule()
        return response
    }

    private func readData(
        for request: URLRequest,
        priority: Float
    ) async throws -> Data {
        guard ResourceLoadingExperiment.isFeatureEnabled(.readRequestCoalescing),
              let key = Self.readRequestCoalescingKey(for: request, priority: priority)
        else {
            return try await data(for: request, priority: priority).0
        }

        return try await BiliReadRequestCoalescer.shared.data(for: key) { [session] in
            try await Self.performReadRequest(
                session: session,
                request: request,
                priority: priority
            )
        }
    }

    private nonisolated static func performReadRequest(
        session: URLSession,
        request: URLRequest,
        priority: Float
    ) async throws -> Data {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let (data, _) = try await BiliNetworkRetry.data(
            session: session,
            request: request,
            priority: priority,
            policy: .api
        )
        ResourceCacheAutoTrim.schedule()
        return data
    }

    private nonisolated static func readRequestCoalescingKey(
        for request: URLRequest,
        priority: Float
    ) -> String? {
        guard let url = request.url,
              (request.httpMethod ?? "GET").uppercased() == "GET"
        else { return nil }

        let headers = (request.allHTTPHeaderFields ?? [:])
            .map { ($0.key.lowercased(), $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "\n")
        let material = [
            url.absoluteString,
            "cache=\(request.cachePolicy.rawValue)",
            "timeout=\(request.timeoutInterval)",
            "priority=\(priority)",
            headers
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func responseCacheKey(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        let referer = request.value(forHTTPHeaderField: "Referer") ?? ""
        let cookieScope = responseCacheCookieScope(request.value(forHTTPHeaderField: "Cookie") ?? "")
        return [
            url.absoluteString,
            "ua:\(userAgent)",
            "ref:\(referer)",
            "cookie:\(cookieScope)"
        ].joined(separator: "\n")
    }

    private nonisolated static func responseCacheCookieScope(_ cookieHeader: String) -> String {
        let mid = cookieValue(named: "DedeUserID", in: cookieHeader) ?? "0"
        let hasSession = cookieValue(named: "SESSDATA", in: cookieHeader) != nil
        let buvid = cookieValue(named: "buvid3", in: cookieHeader) ?? "-"
        return "\(hasSession ? "auth" : "anon")|mid:\(mid)|buvid:\(buvid)"
    }

    private func requireCSRFContext(
        for purpose: BiliAccountPurpose
    ) async throws -> (csrf: String, snapshot: RequestSnapshot) {
        let snapshot = await requestSnapshot(purpose: purpose)
        guard snapshot.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        guard let csrf = snapshot.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return (csrf, snapshot)
    }

    func requireCSRF() async throws -> String {
        try await requireCSRFContext(for: .main).csrf
    }

    private func applyCommonHeaders(to request: inout URLRequest, referer: String, userAgent: String? = nil, cookieHeader: String) {
        BiliURLSessionFactory.apiHeaders(
            referer: referer,
            userAgent: userAgent ?? Self.mobileUserAgent,
            cookieHeader: cookieHeader
        )
        .forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    }

    private func guestModeCookieHeader() async -> String? {
        let snapshot = await requestSnapshot()
        return snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil
    }

    nonisolated static func cookieValue(named name: String, in header: String) -> String? {
        header
            .split(separator: ";")
            .compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name, !pair[1].isEmpty else { return nil }
                return pair[1]
            }
            .first
    }

    private static func cookieHeader(
        _ header: String,
        settingCookieNamed name: String,
        to value: String
    ) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var didReplace = false
        var items = header
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { item -> String in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name else { return item }
                didReplace = true
                return "\(name)=\(trimmedValue)"
            }
        if !didReplace, !trimmedValue.isEmpty {
            items.insert("\(name)=\(trimmedValue)", at: 0)
        }
        return items.joined(separator: "; ")
    }

    static func formBody(from fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static func randomAlphaNumeric(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length))
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    nonisolated static func decode<T: Decodable>(
        _ type: T.Type = T.self,
        from data: Data,
        priority: Float
    ) async throws -> T {
        let taskPriority: TaskPriority
        if priority >= URLSessionTask.highPriority {
            taskPriority = .userInitiated
        } else if priority <= URLSessionTask.lowPriority {
            taskPriority = .background
        } else {
            taskPriority = .utility
        }

        return try await Task.detached(priority: taskPriority) {
            try JSONDecoder.bili.decode(T.self, from: data)
        }.value
    }

    nonisolated static func decode<T: Decodable>(
        _ data: Data,
        priority: Float
    ) async throws -> T {
        try await decode(T.self, from: data, priority: priority)
    }

    func favoriteFolderSummaries(
        rid: Int? = nil,
        context: InteractionRequestContext
    ) async throws -> [FavoriteFolder] {
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let userMID = context.currentUserMID, userMID > 0 else {
            throw BiliAPIError.missingPayload
        }
        var query = [
            "up_mid": String(userMID),
            "type": "2"
        ]
        if let rid {
            query["rid"] = String(rid)
        }
        let response: BiliResponse<FavoriteFolderListData> = try await get(
            base: baseURL,
            path: "/x/v3/fav/folder/created/list-all",
            query: query,
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list ?? []
    }

    private func requirePlayURLData(_ response: BiliResponse<PlayURLData>, requirePlayablePayload: Bool = false) throws -> PlayURLData {
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

    private func requirePgcPlayURLData(_ response: BiliResponse<PgcPlayURLResult>, requirePlayablePayload: Bool = false) throws -> PlayURLData {
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload?.videoInfo else { throw BiliAPIError.missingPayload }
        if let code = data.code, code != 0 {
            throw BiliAPIError.api(code: code, message: data.message)
        }
        if requirePlayablePayload, data.playVariants.isEmpty {
            if data.hasAnyPlayURLPayload {
                throw BiliAPIError.unsupportedHardwarePlayback(
                    "番剧播放接口已返回地址，但没有可用的 HEVC/AAC 硬解组合（\(data.rawPlayURLSummary)）"
                )
            }
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

    private static func fileStem(from url: String) -> String {
        let filename = URL(string: url)?.deletingPathExtension().lastPathComponent
        return filename ?? ""
    }

}

extension JSONDecoder {
    nonisolated static var bili: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}

private extension Float {
    static var userInitiated: Float { URLSessionTask.highPriority }
    static var utility: Float { URLSessionTask.defaultPriority }
    static var background: Float { URLSessionTask.lowPriority }
}

private struct StartupPlayURLAttempt: Sendable {
    let stage: String
    let route: StartupPlayURLRoute?
    let elapsedMilliseconds: Int?
    let data: PlayURLData?
    let error: Error?
    let isAuthoritativePlayURLSource: Bool
}

private struct StartupPlayURLRaceResult: Sendable {
    let data: PlayURLData
    let isVerifiedUnavailablePreferredFallback: Bool
}

nonisolated private struct PiliPlusWBIQualityAttempt: Sendable {
    let queryQuality: Int
    let selectedQuality: Int?
    let data: PlayURLData?
    let elapsedMilliseconds: Double
    let selectionElapsedMilliseconds: Double?
    let responseDiagnostic: String?
    let error: Error?

    var isSuccessful: Bool {
        error == nil && data != nil && selectedQuality != nil
    }
}

nonisolated private struct PiliPlusWebpageHedge: Sendable {
    let scheduledAt: CFTimeInterval
    let delayNanoseconds: UInt64
    let task: Task<PlayURLData, Error>
}

private struct CachedPlayURLFailure {
    let error: BiliAPIError
    let expiresAt: CFTimeInterval
}

private struct CachedUnavailableQuality {
    let fallbackQuality: Int?
    let expiresAt: CFTimeInterval
}

nonisolated private struct PendingPlayURLRequestKey: Hashable, Sendable {
    let cacheKey: PlayURLCacheKey
    let scope: PlayURLCacheLoginScope
}

nonisolated private struct PendingPlayURLRequest: Sendable {
    let id: UUID
    let task: Task<PlayURLData, Error>
}

nonisolated private struct PendingPlayURLStageRequest: Sendable {
    let id: UUID
    let task: Task<PlayURLData, Error>
}

private actor PendingPlayURLRequestStartGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
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

private struct CachedDanmaku {
    let items: [DanmakuItem]
    let storedAt: CFTimeInterval
}

nonisolated private struct FrontendFingerprintData: Decodable {
    let buvid3: String?

    enum CodingKeys: String, CodingKey {
        case buvid3 = "b_3"
    }
}

private actor BiliAPIClientState {
    private struct PersistedWBIKeys: Codable {
        let keys: WBIKeys
        let storedAt: Date
    }

    private static let persistedWBIKeysKey = "cc.bili.persisted-wbi-keys.v1"
    private let playURLFailureCacheLimit = 96
    private let unavailableQualityCacheLimit = 64
    private let unavailableQualityCacheTTL: CFTimeInterval = 10 * 60
    private let danmakuCacheLimit = 12
    private let danmakuCacheTTL: CFTimeInterval = 30 * 60
    private var cachedWBIKeys: WBIKeys?
    private var cachedWBIKeysDate: Date?
    private var wbiKeysTask: Task<WBIKeys, Error>?
    private var navTask: Task<NavUserInfo, Error>?
    private var videoListTasks: [String: Task<[VideoItem], Error>] = [:]
    private var videoDetailTasks: [String: Task<VideoItem, Error>] = [:]
    private var uploaderProfileTasks: [Int: Task<UploaderProfile, Error>] = [:]
    private var appRecommendFeedIndex: Int?
    private let startupWBIHealth = StartupWBIHealthStore()
    private let startupWBIRouteHints = StartupWBIRouteHintStore()
    private var playURLFailureCache: [String: CachedPlayURLFailure] = [:]
    private var unavailableQualityCache: [String: CachedUnavailableQuality] = [:]
    private var playURLRequestTasks: [PendingPlayURLRequestKey: PendingPlayURLRequest] = [:]
    private var playURLStageTasks: [String: PendingPlayURLStageRequest] = [:]
    private var danmakuCache: [Int: CachedDanmaku] = [:]

    func freshCachedWBIKeys() -> WBIKeys? {
        guard let keys = cachedWBIKeys,
              let date = cachedWBIKeysDate,
              Date().timeIntervalSince(date) < 12 * 60 * 60
        else {
            if let persisted = persistedWBIKeys() {
                cachedWBIKeys = persisted.keys
                cachedWBIKeysDate = persisted.storedAt
                return persisted.keys
            }
            return nil
        }
        return keys
    }

    func storeWBIKeys(_ keys: WBIKeys) {
        cachedWBIKeys = keys
        cachedWBIKeysDate = Date()
        wbiKeysTask = nil
        persistWBIKeys(keys)
    }

    func clearWBIKeys() {
        cachedWBIKeys = nil
        cachedWBIKeysDate = nil
        wbiKeysTask = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedWBIKeysKey)
    }

    private func persistedWBIKeys() -> PersistedWBIKeys? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedWBIKeysKey),
              let persisted = try? JSONDecoder().decode(PersistedWBIKeys.self, from: data),
              Date().timeIntervalSince(persisted.storedAt) < 12 * 60 * 60
        else { return nil }
        return persisted
    }

    private func persistWBIKeys(_ keys: WBIKeys) {
        let persisted = PersistedWBIKeys(keys: keys, storedAt: Date())
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedWBIKeysKey)
    }

    func wbiKeysFetchTask() -> Task<WBIKeys, Error>? {
        wbiKeysTask
    }

    func setWBIKeysFetchTask(_ task: Task<WBIKeys, Error>) {
        wbiKeysTask = task
    }

    func clearWBIKeysFetchTask() {
        wbiKeysTask = nil
    }

    func navUserTask() -> Task<NavUserInfo, Error>? {
        navTask
    }

    func setNavUserTask(_ task: Task<NavUserInfo, Error>) {
        navTask = task
    }

    func clearNavUserTask() {
        navTask = nil
    }

    func videoListTask(for key: String) -> Task<[VideoItem], Error>? {
        videoListTasks[key]
    }

    func setVideoListTask(_ task: Task<[VideoItem], Error>, for key: String) {
        videoListTasks[key] = task
    }

    func clearVideoListTask(for key: String) {
        videoListTasks[key] = nil
    }

    func clearHomeRecommendState() {
        appRecommendFeedIndex = nil
        videoListTasks = videoListTasks.filter { key, _ in
            !key.hasPrefix("recommend|")
        }
    }

    func appRecommendFeedIndex(defaulting defaultIndex: Int) -> Int {
        appRecommendFeedIndex ?? defaultIndex
    }

    func setAppRecommendFeedIndex(_ index: Int?) {
        guard let index, index > 0 else {
            appRecommendFeedIndex = nil
            return
        }
        appRecommendFeedIndex = index
    }

    func videoDetailTask(for bvid: String) -> Task<VideoItem, Error>? {
        videoDetailTasks[bvid]
    }

    func setVideoDetailTask(_ task: Task<VideoItem, Error>, for bvid: String) {
        videoDetailTasks[bvid] = task
    }

    func clearVideoDetailTask(for bvid: String) {
        videoDetailTasks[bvid] = nil
    }

    func clearVideoDetailTasks(containing bvid: String) {
        let keys = videoDetailTasks.keys.filter { $0.hasPrefix("bvid:\(bvid)|") }
        for key in keys {
            videoDetailTasks[key]?.cancel()
            videoDetailTasks[key] = nil
        }
    }

    func uploaderProfileTask(for mid: Int) -> Task<UploaderProfile, Error>? {
        uploaderProfileTasks[mid]
    }

    func setUploaderProfileTask(_ task: Task<UploaderProfile, Error>, for mid: Int) {
        uploaderProfileTasks[mid] = task
    }

    func clearUploaderProfileTask(for mid: Int) {
        uploaderProfileTasks[mid] = nil
    }

    func startupWBISuppressionStatus() async -> StartupWBISuppressionStatus? {
        await startupWBIHealth.suppressionStatus()
    }

    func recordStartupWBISuccess() async -> Bool {
        await startupWBIHealth.recordSuccess()
    }

    func recordStartupWBIFailure(reason: String) async -> StartupWBIHealthUpdate {
        await startupWBIHealth.recordFailure(reason: reason)
    }

    func startupWBIRouteHint(for key: StartupWBIRouteHintKey) async -> StartupWBIRouteHint? {
        await startupWBIRouteHints.hint(for: key)
    }

    func storeStartupWBIRouteHint(
        _ hint: StartupWBIRouteHint,
        for key: StartupWBIRouteHintKey
    ) async {
        await startupWBIRouteHints.store(hint, for: key)
    }

    func pendingPlayURLRequest(for key: PendingPlayURLRequestKey) -> PendingPlayURLRequest? {
        playURLRequestTasks[key]
    }

    func insertPendingPlayURLRequestIfAbsent(
        _ request: PendingPlayURLRequest,
        for key: PendingPlayURLRequestKey
    ) -> PendingPlayURLRequest? {
        if let existing = playURLRequestTasks[key] {
            return existing
        }
        playURLRequestTasks[key] = request
        return nil
    }

    func clearPendingPlayURLRequest(for key: PendingPlayURLRequestKey, id: UUID) {
        guard playURLRequestTasks[key]?.id == id else { return }
        playURLRequestTasks[key] = nil
    }

    func playURLStageTask(for key: String) -> PendingPlayURLStageRequest? {
        playURLStageTasks[key]
    }

    func insertPlayURLStageTaskIfAbsent(
        _ request: PendingPlayURLStageRequest,
        for key: String
    ) -> PendingPlayURLStageRequest? {
        if let existing = playURLStageTasks[key] {
            return existing
        }
        playURLStageTasks[key] = request
        return nil
    }

    func clearPlayURLStageTask(for key: String, id: UUID) {
        guard playURLStageTasks[key]?.id == id else { return }
        playURLStageTasks[key] = nil
    }

    func clearPlayURLFailuresAndTasks(containing bvid: String) async {
        guard !bvid.isEmpty else { return }
        await startupWBIRouteHints.clear(containing: bvid)
        let failureKeys = playURLFailureCache.keys.filter { $0.contains("|\(bvid)|") }
        failureKeys.forEach { playURLFailureCache[$0] = nil }
        let unavailableKeys = unavailableQualityCache.keys.filter { $0.contains("|\(bvid)|") }
        unavailableKeys.forEach { unavailableQualityCache[$0] = nil }
        let taskKeys = playURLStageTasks.keys.filter { $0.contains("|\(bvid)|") }
        for key in taskKeys {
            playURLStageTasks[key]?.task.cancel()
            playURLStageTasks[key] = nil
        }
        let requestKeys = playURLRequestTasks.keys.filter { $0.cacheKey.bvid == bvid }
        for key in requestKeys {
            playURLRequestTasks[key]?.task.cancel()
            playURLRequestTasks[key] = nil
        }
    }

    func clearAllPlayURLFailuresAndTasks() async {
        await startupWBIRouteHints.clear()
        playURLFailureCache.removeAll()
        unavailableQualityCache.removeAll()
        for request in playURLStageTasks.values {
            request.task.cancel()
        }
        playURLStageTasks.removeAll()
        for request in playURLRequestTasks.values {
            request.task.cancel()
        }
        playURLRequestTasks.removeAll()
    }

    func cachedDanmaku(for cid: Int) -> [DanmakuItem]? {
        let now = CACurrentMediaTime()
        guard let cached = danmakuCache[cid] else { return nil }
        guard now - cached.storedAt < danmakuCacheTTL else {
            danmakuCache[cid] = nil
            return nil
        }
        return cached.items
    }

    func storeDanmaku(_ items: [DanmakuItem], for cid: Int) {
        danmakuCache[cid] = CachedDanmaku(items: items, storedAt: CACurrentMediaTime())
        trimDanmakuCacheIfNeeded()
    }

    func cancelPlayURLStage(_ key: String) {
        playURLStageTasks[key]?.task.cancel()
        playURLStageTasks[key] = nil
    }

    func cachedPlayURLFailure(for key: String) -> BiliAPIError? {
        let now = CACurrentMediaTime()
        if let cached = playURLFailureCache[key] {
            if cached.expiresAt > now {
                return cached.error
            }
            playURLFailureCache[key] = nil
        }
        trimExpiredPlayURLFailures(now: now)
        return nil
    }

    func cachedUnavailableQuality(for key: String) -> CachedUnavailableQuality? {
        let now = CACurrentMediaTime()
        guard let cached = unavailableQualityCache[key] else { return nil }
        guard cached.expiresAt > now else {
            unavailableQualityCache[key] = nil
            trimExpiredUnavailableQualities(now: now)
            return nil
        }
        return cached
    }

    func storeUnavailableQuality(_ fallbackQuality: Int?, for key: String) {
        let now = CACurrentMediaTime()
        unavailableQualityCache[key] = CachedUnavailableQuality(
            fallbackQuality: fallbackQuality,
            expiresAt: now + unavailableQualityCacheTTL
        )
        trimUnavailableQualityCacheIfNeeded(now: now)
    }

    func storePlayURLFailure(_ error: Error, for key: String) {
        guard let cacheableError = BiliAPIClient.cacheablePlayURLFailure(error) else { return }
        let now = CACurrentMediaTime()
        playURLFailureCache[key] = CachedPlayURLFailure(
            error: cacheableError,
            expiresAt: now + BiliAPIClient.playURLFailureTTL(for: cacheableError)
        )
        trimPlayURLFailureCacheIfNeeded(now: now)
    }

    private func trimExpiredPlayURLFailures(now: CFTimeInterval = CACurrentMediaTime()) {
        playURLFailureCache = playURLFailureCache.filter { $0.value.expiresAt > now }
    }

    private func trimPlayURLFailureCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        trimExpiredPlayURLFailures(now: now)
        guard playURLFailureCache.count > playURLFailureCacheLimit else { return }
        let overflow = playURLFailureCache.count - playURLFailureCacheLimit
        let expiredKeys = playURLFailureCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        expiredKeys.forEach { playURLFailureCache[$0] = nil }
    }

    private func trimExpiredUnavailableQualities(now: CFTimeInterval = CACurrentMediaTime()) {
        unavailableQualityCache = unavailableQualityCache.filter { $0.value.expiresAt > now }
    }

    private func trimUnavailableQualityCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        trimExpiredUnavailableQualities(now: now)
        guard unavailableQualityCache.count > unavailableQualityCacheLimit else { return }
        let overflow = unavailableQualityCache.count - unavailableQualityCacheLimit
        let expiredKeys = unavailableQualityCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        expiredKeys.forEach { unavailableQualityCache[$0] = nil }
    }

    private func trimDanmakuCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        danmakuCache = danmakuCache.filter { now - $0.value.storedAt < danmakuCacheTTL }
        guard danmakuCache.count > danmakuCacheLimit else { return }
        let overflow = danmakuCache.count - danmakuCacheLimit
        let oldestKeys = danmakuCache
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflow)
            .map(\.key)
        oldestKeys.forEach { danmakuCache[$0] = nil }
    }
}

import Foundation
import OSLog
import QuartzCore

extension BiliAPIClient {
    private func preferredVideoQuality() async -> Int? {
        let snapshot = requestSnapshot()
        return snapshot.effectivePreferredVideoQuality
    }

    func fetchStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil,
        requestLease: StartupPlayURLRequestLease? = nil,
        requestSource: StartupPlayURLRequestSource = .preload
    ) async throws -> PlayURLData {
        let snapshot = requestSnapshot(purpose: .playback)
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

    func fetchWBIStartupPlayURL(
        bvid: String,
        cid: Int,
        keys: WBIKeys,
        preferredQuality: Int?
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = requestSnapshot(purpose: .playback)
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
                priority: URLSessionTask.highPriority,
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
                    priority: URLSessionTask.highPriority,
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
                priority: URLSessionTask.highPriority,
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
                    priority: URLSessionTask.highPriority,
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
                priority: URLSessionTask.highPriority,
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
}

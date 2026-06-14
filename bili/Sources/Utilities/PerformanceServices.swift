import AVFoundation
import Combine
import ImageIO
import OSLog
import SwiftUI
import UIKit

enum VideoPreloadMediaWarmupMode: Sendable {
    case full
    case routePlanOnly

    nonisolated var isRoutePlanOnly: Bool {
        if case .routePlanOnly = self {
            return true
        }
        return false
    }
}

actor VideoPreloadCenter {
    static let shared = VideoPreloadCenter()

    private let maxConcurrentPreloads = 3
    private let cachedPlayURLTTL: TimeInterval = 12 * 60
    private let stalePlayablePlayURLTTL: TimeInterval = 20 * 60
    private let maxCachedPlayURLCount = 32
    private let cachedDetailTTL: TimeInterval = 180
    private let maxCachedDetailCount = 24
    private let cachedRelatedTTL: TimeInterval = 8 * 60
    private let maxCachedRelatedCount = 32
    private let mediaWarmupTTL: TimeInterval = 120
    private let maxMediaWarmupCount = 32
    private var defaultPreferredQuality: Int?
    private var defaultTargetPreferredQuality: Int?
    private var tasks: [String: Task<PlayURLData?, Never>] = [:]
    private var taskUserInitiatedFlags: [String: Bool] = [:]
    private var taskPreferredQualities: [String: Int?] = [:]
    private var detailTasks: [String: Task<VideoItem, Error>] = [:]
    private var detailTaskUserInitiatedFlags: [String: Bool] = [:]
    private var relatedTasks: [String: Task<[VideoItem], Error>] = [:]
    private var bvidPlayInfoTasks: [String: Task<PlayURLData?, Never>] = [:]
    private var bvidPlayInfoTaskPreferredQualities: [String: Int?] = [:]
    private var bvidPlayInfoCache: [String: CachedPlayURL] = [:]
    private var mediaWarmupTasks: [String: Task<Void, Never>] = [:]
    private var activeOrder: [String] = []
    private var playURLCache: [String: CachedPlayURL] = [:]
    private var detailCache: [String: CachedVideoDetail] = [:]
    private var relatedCache: [String: CachedRelatedVideos] = [:]
    private var recentRelatedCandidates: [VideoItem] = []
    private var mediaWarmupCache: [String: Date] = [:]
    private var focusedPlaybackBVID: String?
    private var focusedPlaybackUntil: Date?
    private var defaultCDNPreference: PlaybackCDNPreference = .automatic

    func updatePlaybackPreferences(
        preferredQuality: Int?,
        targetPreferredQuality: Int? = nil,
        cdnPreference: PlaybackCDNPreference = .automatic,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile = .normal
    ) {
        defaultPreferredQuality = Self.effectiveStartupQuality(
            preferredQuality,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
        defaultTargetPreferredQuality = targetPreferredQuality ?? preferredQuality
        defaultCDNPreference = cdnPreference
    }

    func cachedPlayURLMissingPreferredQuality(for bvid: String, cid: Int, page: Int?, preferredQuality: Int?) -> Bool {
        guard let preferredQuality,
              let cached = cachedPlayURL(for: bvid, cid: cid, page: page, preferredQuality: preferredQuality)
        else { return false }
        let playableVariants = cached.playVariants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        return !playableVariants.contains(where: { $0.quality == preferredQuality })
    }

    func preload(
        _ video: VideoItem,
        api: BiliAPIClient,
        warmsMedia: Bool = true,
        mediaWarmupMode: VideoPreloadMediaWarmupMode = .full,
        mediaWarmupDelay: TimeInterval = 1.25,
        priority: TaskPriority = .utility,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile = .normal
    ) {
        guard shouldAllowPreload(bvid: video.bvid, priority: priority) else { return }
        guard let cid = video.cid else {
            preloadDetailAndPlayback(
                video,
                api: api,
                warmsMedia: warmsMedia,
                mediaWarmupMode: mediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            return
        }
        preloadPlayURL(
            bvid: video.bvid,
            cid: cid,
            page: nil,
            api: api,
            warmsMedia: warmsMedia,
            mediaWarmupMode: mediaWarmupMode,
            mediaWarmupDelay: mediaWarmupDelay,
            priority: priority,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
    }

    func preloadPlayInfo(
        _ video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int?,
        targetPreferredQuality: Int? = nil,
        cdnPreference: PlaybackCDNPreference = .automatic,
        priority: TaskPriority = .utility,
        warmsMedia: Bool = false,
        mediaWarmupMode: VideoPreloadMediaWarmupMode = .full,
        mediaWarmupDelay: TimeInterval = 0,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile = .normal
    ) {
        let isStartupPackageWarmup = warmsMedia
        guard isStartupPackageWarmup
                || playbackAdaptationProfile.level.rawValue < PlayerPlaybackAdaptationProfile.Level.slow.rawValue
                || priority == .userInitiated
        else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadSkipped reason=adaptiveSlow bvid=\(video.bvid, privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public)"
            )
            return
        }
        guard isStartupPackageWarmup
                || !PlaybackEnvironment.current.shouldPreferConservativePlayback
                || priority == .userInitiated
        else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadSkipped reason=conservative bvid=\(video.bvid, privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public)"
            )
            return
        }
        let effectivePreferredQuality = Self.effectiveStartupQuality(
            preferredQuality,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
        let effectiveTargetPreferredQuality = targetPreferredQuality
            ?? preferredQuality
            ?? defaultTargetPreferredQuality
            ?? defaultPreferredQuality
        defaultPreferredQuality = effectivePreferredQuality
        defaultTargetPreferredQuality = effectiveTargetPreferredQuality
        defaultCDNPreference = cdnPreference
        let effectiveWarmsMedia = warmsMedia
        let effectiveMediaWarmupMode = mediaWarmupMode
        guard let cid = video.cid else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadDetailStart bvid=\(video.bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) priority=\(String(describing: priority), privacy: .public)"
            )
            preloadWebPagePlayInfo(
                bvid: video.bvid,
                api: api,
                preferredQuality: effectivePreferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                priority: priority
            )
            preloadDetailAndPlayback(
                video,
                api: api,
                preferredQuality: effectivePreferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                cdnPreference: cdnPreference,
                warmsMedia: effectiveWarmsMedia,
                mediaWarmupMode: effectiveMediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            return
        }
        preloadPlayURL(
            bvid: video.bvid,
            cid: cid,
            page: nil,
            preferredQuality: effectivePreferredQuality,
            targetPreferredQuality: effectiveTargetPreferredQuality,
            cdnPreference: cdnPreference,
            api: api,
            warmsMedia: effectiveWarmsMedia,
            mediaWarmupMode: effectiveMediaWarmupMode,
            mediaWarmupDelay: mediaWarmupDelay,
            priority: priority,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
    }

    private func preloadPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int? = nil,
        targetPreferredQuality: Int? = nil,
        cdnPreference: PlaybackCDNPreference? = nil,
        api: BiliAPIClient,
        warmsMedia: Bool,
        mediaWarmupMode: VideoPreloadMediaWarmupMode,
        mediaWarmupDelay: TimeInterval,
        priority: TaskPriority,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        let effectivePreferredQuality = Self.effectiveStartupQuality(
            preferredQuality ?? defaultPreferredQuality,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
        let effectiveTargetPreferredQuality = targetPreferredQuality
            ?? defaultTargetPreferredQuality
            ?? preferredQuality
            ?? defaultPreferredQuality
        let effectiveCDNPreference = cdnPreference ?? defaultCDNPreference
        guard shouldAllowPreload(bvid: bvid, priority: priority) else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadSkipped reason=focusedPlayback bvid=\(bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public)"
            )
            return
        }
        let key = cacheKey(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: effectivePreferredQuality
        )
        let cachedDataMissesPreferredQuality = cachedPlayURLMissingPreferredQuality(
            for: bvid,
            cid: cid,
            page: page,
            preferredQuality: effectivePreferredQuality
        )
        let start = CACurrentMediaTime()
        if tasks[key] != nil {
            guard priority == .userInitiated, taskUserInitiatedFlags[key] != true else { return }
            tasks[key]?.cancel()
            tasks[key] = nil
            taskUserInitiatedFlags[key] = nil
            taskPreferredQualities[key] = nil
            activeOrder.removeAll { $0 == key }
        }
        if let cachedData = cachedPlayURL(
            for: bvid,
            cid: cid,
            page: page,
            preferredQuality: effectivePreferredQuality
        ),
           !cachedDataMissesPreferredQuality {
            let playableCount = cachedData.playVariants.filter(\.isPlayable).count
            PlayerMetricsLog.logger.info(
                "playInfoPreloadCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) playable=\(playableCount, privacy: .public) warmsMedia=\(warmsMedia, privacy: .public)"
            )
            if warmsMedia {
                store(
                    cachedData,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: effectivePreferredQuality,
                    targetPreferredQuality: effectiveTargetPreferredQuality,
                    cdnPreference: effectiveCDNPreference,
                    warmsMedia: true,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay
                )
            }
            return
        }
        trimIfNeeded()
        activeOrder.append(key)
        taskUserInitiatedFlags[key] = priority == .userInitiated
        taskPreferredQualities[key] = effectivePreferredQuality
        PlayerMetricsLog.logger.info(
            "playInfoPreloadStart bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) warmsMedia=\(warmsMedia, privacy: .public) priority=\(String(describing: priority), privacy: .public)"
        )
        tasks[key] = Task(priority: priority) {
            do {
                let data: PlayURLData
                data = try await api.fetchStartupPlayURL(
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: effectivePreferredQuality,
                    startupQualityCeiling: nil
                )
                guard !Task.isCancelled else {
                    self.finish(key)
                    return nil
                }
                self.store(
                    data,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: effectivePreferredQuality,
                    targetPreferredQuality: effectiveTargetPreferredQuality,
                    cdnPreference: effectiveCDNPreference,
                    warmsMedia: warmsMedia,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay
                )
                let playableCount = data.playVariants.filter(\.isPlayable).count
                PlayerMetricsLog.logger.info(
                    "playInfoPreloadComplete bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) playable=\(playableCount, privacy: .public) qualities=\(Self.qualitySummary(data.playVariants), privacy: .public)"
                )
                self.finish(key)
                return data
            } catch {
                PlayerMetricsLog.logger.info(
                    "playInfoPreloadFailed bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                self.finish(key)
                return nil
            }
        }
    }

    func preloadDetailAndPlayback(
        _ video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int? = nil,
        targetPreferredQuality: Int? = nil,
        cdnPreference: PlaybackCDNPreference? = nil,
        warmsMedia: Bool = true,
        mediaWarmupMode: VideoPreloadMediaWarmupMode = .full,
        mediaWarmupDelay: TimeInterval = 1.25,
        priority: TaskPriority = .utility,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile = .normal
    ) {
        guard shouldAllowPreload(bvid: video.bvid, priority: priority) else { return }
        let effectivePreferredQuality = Self.effectiveStartupQuality(
            preferredQuality ?? defaultPreferredQuality,
            playbackAdaptationProfile: playbackAdaptationProfile
        )
        let effectiveTargetPreferredQuality = targetPreferredQuality
            ?? defaultTargetPreferredQuality
            ?? preferredQuality
            ?? defaultPreferredQuality
        let effectiveWarmsMedia = warmsMedia
        let effectiveMediaWarmupMode = mediaWarmupMode
        if let cid = video.cid {
            preloadPlayURL(
                bvid: video.bvid,
                cid: cid,
                page: nil,
                preferredQuality: effectivePreferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                cdnPreference: cdnPreference,
                api: api,
                warmsMedia: effectiveWarmsMedia,
                mediaWarmupMode: effectiveMediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            return
        }
        guard !video.bvid.isEmpty else { return }
        if let cached = cachedDetail(for: video.bvid) {
            guard let cid = cached.cid ?? cached.pages?.first?.cid else { return }
            preloadPlayURL(
                bvid: cached.bvid,
                cid: cid,
                page: nil,
                preferredQuality: effectivePreferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                cdnPreference: cdnPreference,
                api: api,
                warmsMedia: effectiveWarmsMedia,
                mediaWarmupMode: effectiveMediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            return
        }
        preloadWebPagePlayInfo(
            bvid: video.bvid,
            api: api,
            preferredQuality: effectivePreferredQuality,
            targetPreferredQuality: effectiveTargetPreferredQuality,
            priority: priority
        )
        if let detailTask = detailTasks[video.bvid] {
            if priority == .userInitiated {
                detailTaskUserInitiatedFlags[video.bvid] = true
            }
            PlayerMetricsLog.logger.info(
                "playInfoPreloadJoinDetail bvid=\(video.bvid, privacy: .public) preferred=\(preferredQuality ?? self.defaultPreferredQuality ?? 0, privacy: .public) priority=\(String(describing: priority), privacy: .public)"
            )
            preloadPlayURLAfterDetail(
                detailTask,
                api: api,
                preferredQuality: effectivePreferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                cdnPreference: cdnPreference,
                warmsMedia: effectiveWarmsMedia,
                mediaWarmupMode: effectiveMediaWarmupMode,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            return
        }

        detailTaskUserInitiatedFlags[video.bvid] = priority == .userInitiated
        detailTasks[video.bvid] = Task(priority: priority) { [bvid = video.bvid] in
            do {
                let detail = try await api.fetchVideoDetail(bvid: bvid)
                guard !Task.isCancelled else {
                    self.finishDetail(bvid)
                    throw CancellationError()
                }
                self.storeDetail(detail)
                if let cid = detail.cid ?? detail.pages?.first?.cid {
                    if await self.storeBVIDPlayInfoIfAvailable(
                        bvid: detail.bvid,
                        cid: cid,
                        page: nil,
                        preferredQuality: effectivePreferredQuality,
                        targetPreferredQuality: effectiveTargetPreferredQuality,
                        cdnPreference: cdnPreference,
                        warmsMedia: effectiveWarmsMedia,
                        mediaWarmupMode: effectiveMediaWarmupMode,
                        mediaWarmupDelay: mediaWarmupDelay
                    ) {
                        self.finishDetail(bvid)
                        return detail
                    }
                    self.preloadPlayURL(
                        bvid: detail.bvid,
                        cid: cid,
                        page: nil,
                        preferredQuality: effectivePreferredQuality,
                        targetPreferredQuality: effectiveTargetPreferredQuality,
                        cdnPreference: cdnPreference,
                        api: api,
                        warmsMedia: effectiveWarmsMedia,
                        mediaWarmupMode: effectiveMediaWarmupMode,
                        mediaWarmupDelay: mediaWarmupDelay,
                        priority: priority,
                        playbackAdaptationProfile: playbackAdaptationProfile
                    )
                }
                self.finishDetail(bvid)
                return detail
            } catch {
                self.finishDetail(bvid)
                throw error
            }
        }
    }

    private func preloadPlayURLAfterDetail(
        _ detailTask: Task<VideoItem, Error>,
        api: BiliAPIClient,
        preferredQuality: Int?,
        targetPreferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference?,
        warmsMedia: Bool,
        mediaWarmupMode: VideoPreloadMediaWarmupMode,
        mediaWarmupDelay: TimeInterval,
        priority: TaskPriority,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) {
        Task(priority: priority) {
            do {
                let detail = try await detailTask.value
                guard !Task.isCancelled,
                      let cid = detail.cid ?? detail.pages?.first?.cid
                else { return }
                if await self.storeBVIDPlayInfoIfAvailable(
                    bvid: detail.bvid,
                    cid: cid,
                    page: nil,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    warmsMedia: warmsMedia,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay
                ) {
                    return
                }
                self.preloadPlayURL(
                    bvid: detail.bvid,
                    cid: cid,
                    page: nil,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    api: api,
                    warmsMedia: warmsMedia,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay,
                    priority: priority,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
            } catch {
                guard !Task.isCancelled else { return }
                PlayerMetricsLog.logger.info(
                    "playInfoPreloadJoinDetailFailed preferred=\(preferredQuality ?? self.defaultPreferredQuality ?? 0, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func preloadWebPagePlayInfo(
        bvid: String,
        api: BiliAPIClient,
        preferredQuality: Int?,
        targetPreferredQuality: Int? = nil,
        priority: TaskPriority
    ) {
        guard !bvid.isEmpty else { return }
        trimExpiredBVIDPlayInfo()
        let effectivePreferredQuality = preferredQuality ?? defaultPreferredQuality
        let key = bvidPlayInfoKey(bvid: bvid, preferredQuality: effectivePreferredQuality)
        if let cached = bvidPlayInfoCache[key],
           !cached.data.shouldRefetchForPreferredQuality(effectivePreferredQuality ?? 0) {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadWebpageCacheHit bvid=\(bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public)"
            )
            return
        }
        if bvidPlayInfoTasks[key] != nil {
            return
        }
        let start = CACurrentMediaTime()
        bvidPlayInfoTaskPreferredQualities[key] = effectivePreferredQuality
        PlayerMetricsLog.logger.info(
            "playInfoPreloadWebpageStart bvid=\(bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) priority=\(String(describing: priority), privacy: .public)"
        )
        bvidPlayInfoTasks[key] = Task(priority: priority) {
            do {
                let data = try await api.fetchWebPagePlayURL(
                    bvid: bvid,
                    cid: 0,
                    page: nil,
                    preferredQuality: effectivePreferredQuality
                )
                guard !Task.isCancelled else {
                    self.finishBVIDPlayInfo(key)
                    return nil
                }
                self.storeBVIDPlayInfo(data, for: key)
                self.trimBVIDPlayInfoCacheIfNeeded()
                PlayerMetricsLog.logger.info(
                    "playInfoPreloadWebpageComplete bvid=\(bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) qualities=\(Self.qualitySummary(data.playVariants), privacy: .public)"
                )
                self.finishBVIDPlayInfo(key)
                return data
            } catch {
                guard !Task.isCancelled else {
                    self.finishBVIDPlayInfo(key)
                    return nil
                }
                PlayerMetricsLog.logger.info(
                    "playInfoPreloadWebpageFailed bvid=\(bvid, privacy: .public) preferred=\(effectivePreferredQuality ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                self.finishBVIDPlayInfo(key)
                return nil
            }
        }
    }

    private func storeBVIDPlayInfoIfAvailable(
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int?,
        targetPreferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference?,
        warmsMedia: Bool,
        mediaWarmupMode: VideoPreloadMediaWarmupMode,
        mediaWarmupDelay: TimeInterval
    ) async -> Bool {
        let effectivePreferredQuality = preferredQuality ?? defaultPreferredQuality
        let effectiveTargetPreferredQuality = targetPreferredQuality
            ?? defaultTargetPreferredQuality
            ?? preferredQuality
            ?? defaultPreferredQuality
        let effectiveCDNPreference = cdnPreference ?? defaultCDNPreference
        if let cached = cachedPlayURL(
            for: bvid,
            cid: cid,
            page: page,
            preferredQuality: effectivePreferredQuality
        ), !cached.shouldRefetchForPreferredQuality(effectivePreferredQuality ?? 0) {
            return true
        }
        let keys = bvidPlayInfoKeys(bvid: bvid, preferredQuality: effectivePreferredQuality)
        for key in keys {
            if let cached = bvidPlayInfoCache[key] {
                return storeBVIDPlayInfoDataIfNeeded(
                    cached.data,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: effectivePreferredQuality,
                    targetPreferredQuality: effectiveTargetPreferredQuality,
                    cdnPreference: effectiveCDNPreference,
                    warmsMedia: warmsMedia,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay,
                    source: "cache"
                )
            }
            if let task = bvidPlayInfoTasks[key] {
                if let data = await task.value {
                    return storeBVIDPlayInfoDataIfNeeded(
                        data,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        preferredQuality: effectivePreferredQuality,
                        targetPreferredQuality: effectiveTargetPreferredQuality,
                        cdnPreference: effectiveCDNPreference,
                        warmsMedia: warmsMedia,
                        mediaWarmupMode: mediaWarmupMode,
                        mediaWarmupDelay: mediaWarmupDelay,
                        source: "pending"
                    )
                }
            }
        }
        return false
    }

    private nonisolated static func effectiveStartupQuality(
        _ preferredQuality: Int?,
        playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    ) -> Int? {
        preferredQuality ?? LibraryStore.defaultPreferredVideoQuality
    }

    private func storeBVIDPlayInfoDataIfNeeded(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int?,
        targetPreferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference?,
        warmsMedia: Bool,
        mediaWarmupMode: VideoPreloadMediaWarmupMode,
        mediaWarmupDelay: TimeInterval,
        source: String
    ) -> Bool {
        let effectivePage = normalizedPage(page)
        if let preferredQuality,
           data.shouldRefetchForPreferredQuality(preferredQuality) {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadWebpageBypass bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(preferredQuality, privacy: .public) source=\(source, privacy: .public) available=\(Self.qualitySummary(data.playVariants), privacy: .public)"
            )
            return false
        }
        if let cached = cachedPlayURL(
            for: bvid,
            cid: cid,
            page: effectivePage,
            preferredQuality: preferredQuality
        ) {
            let cachedMatchesPreferredQuality = preferredQuality.map {
                !cached.shouldRefetchForPreferredQuality($0)
            } ?? true
            guard cachedMatchesPreferredQuality else { return false }
            if warmsMedia {
                store(
                    cached,
                    bvid: bvid,
                    cid: cid,
                    page: effectivePage,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    warmsMedia: true,
                    mediaWarmupMode: mediaWarmupMode,
                    mediaWarmupDelay: mediaWarmupDelay
                )
            }
            return true
        }
        store(
            data,
            bvid: bvid,
            cid: cid,
            page: effectivePage,
            preferredQuality: preferredQuality,
            targetPreferredQuality: targetPreferredQuality,
            cdnPreference: cdnPreference,
            warmsMedia: warmsMedia,
            mediaWarmupMode: mediaWarmupMode,
            mediaWarmupDelay: mediaWarmupDelay
        )
        PlayerMetricsLog.logger.info(
            "playInfoPreloadWebpageApplied bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public) source=\(source, privacy: .public)"
        )
        return true
    }

    private func cachedOrPendingBVIDPlayInfo(
        for bvid: String,
        preferredQuality: Int?,
        maximumPendingWait: UInt64? = nil
    ) async -> PlayURLData? {
        trimExpiredBVIDPlayInfo()
        let effectivePreferredQuality = preferredQuality ?? defaultPreferredQuality
        let keys = bvidPlayInfoKeys(bvid: bvid, preferredQuality: effectivePreferredQuality)
        for key in keys {
            if let cached = bvidPlayInfoCache[key] {
                return cached.data
            }
            if let task = bvidPlayInfoTasks[key] {
                if let maximumPendingWait {
                    guard maximumPendingWait > 0 else { return nil }
                    return await waitForCachedBVIDPlayInfo(
                        bvid: bvid,
                        preferredQuality: effectivePreferredQuality,
                        timeout: maximumPendingWait
                    )
                }
                return await task.value
            }
        }
        return nil
    }

    func cachedDetail(for bvid: String) -> VideoItem? {
        trimExpiredDetails()
        return detailCache[bvid]?.detail
    }

    func cachedOrPendingDetail(for bvid: String) async -> VideoItem? {
        if let cached = cachedDetail(for: bvid) {
            return cached
        }
        guard let task = detailTasks[bvid] else { return nil }
        _ = try? await task.value
        return cachedDetail(for: bvid)
    }

    func detail(for bvid: String, api: BiliAPIClient, priority: TaskPriority = .userInitiated) async throws -> VideoItem {
        if let cached = cachedDetail(for: bvid) {
            return cached
        }
        if let task = detailTasks[bvid] {
            if priority == .userInitiated {
                detailTaskUserInitiatedFlags[bvid] = true
            }
            return try await task.value
        }

        detailTaskUserInitiatedFlags[bvid] = priority == .userInitiated
        let task = Task(priority: priority) { [bvid] in
            do {
                let detail = try await api.fetchVideoDetail(bvid: bvid)
                guard !Task.isCancelled else {
                    self.finishDetail(bvid)
                    throw CancellationError()
                }
                self.storeDetail(detail)
                self.finishDetail(bvid)
                return detail
            } catch {
                self.finishDetail(bvid)
                throw error
            }
        }
        detailTasks[bvid] = task
        return try await task.value
    }

    func storeDetail(_ detail: VideoItem) {
        guard !detail.bvid.isEmpty else { return }
        detailCache[detail.bvid] = CachedVideoDetail(detail: detail, date: Date())
        trimDetailCacheIfNeeded()
    }

    func cachedRelatedVideos(for bvid: String, limit: Int? = nil) -> [VideoItem]? {
        trimExpiredRelated()
        guard let cached = relatedCache[bvid]?.videos, !cached.isEmpty else { return nil }
        return Self.limitedRelatedVideos(cached, limit: limit)
    }

    func fallbackRelatedVideos(excluding bvid: String, limit: Int? = nil) -> [VideoItem] {
        trimExpiredRelated()
        let candidates = recentRelatedCandidates.filter { !$0.bvid.isEmpty && $0.bvid != bvid }
        return Self.limitedRelatedVideos(candidates, limit: limit)
    }

    func relatedVideos(
        for bvid: String,
        api: BiliAPIClient,
        priority: TaskPriority = .utility,
        limit: Int? = nil
    ) async throws -> [VideoItem] {
        if let cached = cachedRelatedVideos(for: bvid, limit: limit) {
            return cached
        }
        return try await refreshRelatedVideos(
            for: bvid,
            api: api,
            priority: priority,
            limit: limit
        )
    }

    func refreshRelatedVideos(
        for bvid: String,
        api: BiliAPIClient,
        priority: TaskPriority = .utility,
        limit: Int? = nil
    ) async throws -> [VideoItem] {
        if let task = relatedTasks[bvid] {
            return try await task.value
        }

        let task = Task(priority: priority) { [bvid, limit] in
            do {
                let videos = Self.limitedRelatedVideos(
                    try await api.fetchVideoRelated(bvid: bvid),
                    limit: limit
                )
                guard !Task.isCancelled else {
                    self.finishRelated(bvid)
                    throw CancellationError()
                }
                self.storeRelatedVideos(videos, for: bvid)
                self.finishRelated(bvid)
                return videos
            } catch {
                self.finishRelated(bvid)
                throw error
            }
        }
        relatedTasks[bvid] = task
        return try await task.value
    }

    func storeRelatedVideos(_ videos: [VideoItem], for bvid: String) {
        guard !bvid.isEmpty, !videos.isEmpty else { return }
        relatedCache[bvid] = CachedRelatedVideos(videos: videos, date: Date())
        rememberRelatedCandidates(videos, excluding: bvid)
        trimRelatedCacheIfNeeded()
    }

    private nonisolated static func limitedRelatedVideos(_ videos: [VideoItem], limit: Int?) -> [VideoItem] {
        guard let limit else { return videos }
        guard limit > 0 else { return [] }
        return Array(videos.prefix(limit))
    }

    func cachedPlayURL(
        for bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int? = nil
    ) -> PlayURLData? {
        trimExpiredPlayURLs()
        let effectivePage = normalizedPage(page)
        if let entry = playURLCache[cacheKey(
            bvid: bvid,
            cid: cid,
            page: effectivePage,
            preferredQuality: preferredQuality
        )] {
            return entry.data
        }
        if let entry = playURLCache[cacheKey(bvid: bvid, cid: cid, page: effectivePage)] {
            return entry.data
        }
        guard effectivePage != nil else { return nil }
        return playURLCache[cacheKey(
            bvid: bvid,
            cid: cid,
            page: nil,
            preferredQuality: preferredQuality
        )]?.data ?? playURLCache[cacheKey(bvid: bvid, cid: cid, page: nil)]?.data
    }

    func cachedPlayablePlayURL(
        for bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int? = nil
    ) -> PlayURLData? {
        trimExpiredPlayURLs(allowStalePlayable: true)
        let effectivePage = normalizedPage(page)
        let keys = pendingCacheKeys(
            bvid: bvid,
            cid: cid,
            page: effectivePage,
            preferredQuality: preferredQuality
        )
        for key in keys {
            guard let entry = playURLCache[key],
                  entry.data.hasPlayableStreamPayload
            else { continue }
            return entry.data
        }
        return nil
    }

    func cachedOrPendingPlayURL(for bvid: String, cid: Int, page: Int?) async -> PlayURLData? {
        await cachedOrPendingPlayURL(for: bvid, cid: cid, page: page, waitsForPending: true)
    }

    func cachedOrPendingPlayURL(
        for bvid: String,
        cid: Int,
        page: Int?,
        waitsForPending: Bool,
        preferredQuality: Int? = nil,
        maximumPendingWait: UInt64? = nil
    ) async -> PlayURLData? {
        if let cached = cachedPlayURL(
            for: bvid,
            cid: cid,
            page: page,
            preferredQuality: preferredQuality
        ) {
            if let preferredQuality,
               cached.shouldRefetchForPreferredQuality(preferredQuality) {
                return nil
            }
            return cached
        }
        guard waitsForPending else { return nil }

        let keys = pendingCacheKeys(
            bvid: bvid,
            cid: cid,
            page: page,
            preferredQuality: preferredQuality
        )
        guard let pendingKey = keys.first(where: { key in
            guard tasks[key] != nil else { return false }
            guard let preferredQuality else { return true }
            return taskPreferredQualities[key] == preferredQuality
        }),
        let task = tasks[pendingKey]
        else {
            if let data = await cachedOrPendingBVIDPlayInfo(
                for: bvid,
                preferredQuality: preferredQuality,
                maximumPendingWait: maximumPendingWait
            ) {
                if !storeBVIDPlayInfoDataIfNeeded(
                    data,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: defaultTargetPreferredQuality,
                    cdnPreference: defaultCDNPreference,
                    warmsMedia: false,
                    mediaWarmupMode: .full,
                    mediaWarmupDelay: 0,
                    source: "detailWait"
                ) {
                    return nil
                }
                return cachedPlayURL(for: bvid, cid: cid, page: page, preferredQuality: preferredQuality)
            }
            return nil
        }
        if let maximumPendingWait {
            guard maximumPendingWait > 0 else { return nil }
            return await waitForCachedPlayURL(
                bvid: bvid,
                cid: cid,
                page: page,
                preferredQuality: preferredQuality,
                timeout: maximumPendingWait
            )
        } else {
            _ = await task.value
        }
        return cachedPlayURL(for: bvid, cid: cid, page: page, preferredQuality: preferredQuality)
    }

    func store(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int? = nil,
        targetPreferredQuality: Int? = nil,
        cdnPreference: PlaybackCDNPreference? = nil,
        warmsMedia: Bool = true,
        mediaWarmupMode: VideoPreloadMediaWarmupMode = .full,
        mediaWarmupDelay: TimeInterval = 0
    ) {
        guard data.hasPlayableStreamPayload else { return }
        let effectivePage = normalizedPage(page)
        let effectiveCDNPreference = cdnPreference ?? defaultCDNPreference
        let effectiveTargetPreferredQuality = targetPreferredQuality
            ?? defaultTargetPreferredQuality
            ?? preferredQuality
            ?? defaultPreferredQuality
        let now = Date()
        let expiresAt = PlayURLMediaExpiration.expirationDate(for: data, storedAt: now, fallbackTTL: cachedPlayURLTTL)
        guard PlayURLMediaExpiration.isReusable(expirationDate: expiresAt, now: now) else { return }
        playURLCache[cacheKey(bvid: bvid, cid: cid, page: effectivePage)] = CachedPlayURL(
            data: data,
            date: now,
            expiresAt: expiresAt
        )
        if let preferredQuality {
            playURLCache[cacheKey(
                bvid: bvid,
                cid: cid,
                page: effectivePage,
                preferredQuality: preferredQuality
            )] = CachedPlayURL(
                data: data,
                date: now,
                expiresAt: expiresAt
            )
        }
        if warmsMedia {
            scheduleStartupPackageWarmup(
                data,
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality,
                targetPreferredQuality: effectiveTargetPreferredQuality,
                page: effectivePage,
                cdnPreference: effectiveCDNPreference,
                mediaWarmupMode: mediaWarmupMode,
                delay: mediaWarmupDelay
            )
        }
        trimPlayURLCacheIfNeeded()
    }

    @discardableResult
    func warmVariantAndWait(
        _ variant: PlayVariant,
        bvid: String,
        timeout: TimeInterval = 1.2
    ) async -> Bool {
        guard let source = PlayableMediaWarmupSource(variant: variant) else { return false }
        let warmupTask = Task(priority: .userInitiated) {
            await Self.warmPlayableMedia(source, bvid: bvid)
        }
        let timeoutTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return false
        }
        let didWarm = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { await warmupTask.value }
            group.addTask { await timeoutTask.value }
            let result = await group.next() ?? false
            group.cancelAll()
            warmupTask.cancel()
            timeoutTask.cancel()
            return result
        }
        if didWarm {
            mediaWarmupCache["manual|\(bvid)|\(variant.quality)|\(source.identity)"] = Date()
            trimMediaWarmupCacheIfNeeded()
        }
        return didWarm
    }

    @discardableResult
    func warmVariantAndWaitCached(
        _ variant: PlayVariant,
        bvid: String,
        cid: Int,
        page: Int?,
        delay: TimeInterval = 0,
        timeout: TimeInterval = 1.2
    ) async -> Bool {
        guard let source = PlayableMediaWarmupSource(variant: variant) else { return false }
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page),
            "variant",
            String(variant.quality),
            source.identity
        ].joined(separator: "|")

        trimExpiredMediaWarmups()
        if mediaWarmupCache[key] != nil {
            return true
        }
        if let existingTask = mediaWarmupTasks[key] {
            let timeoutTask = Task(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let didWarm = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask {
                    _ = await existingTask.value
                    return await self.mediaWarmupCache[key] != nil
                }
                group.addTask { await timeoutTask.value }
                let result = await group.next() ?? false
                group.cancelAll()
                timeoutTask.cancel()
                return result
            }
            return didWarm
        }

        scheduleMediaWarmup(source, bvid: bvid, key: key, delay: delay)
        guard let scheduledTask = mediaWarmupTasks[key] else { return false }
        let timeoutTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return false
        }
        let didWarm = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                _ = await scheduledTask.value
                return await self.mediaWarmupCache[key] != nil
            }
            group.addTask { await timeoutTask.value }
            let result = await group.next() ?? false
            group.cancelAll()
            timeoutTask.cancel()
            return result
        }
        return didWarm
    }

    func warmVariant(
        _ variant: PlayVariant,
        bvid: String,
        cid: Int,
        page: Int?,
        delay: TimeInterval = 0
    ) {
        guard let source = PlayableMediaWarmupSource(variant: variant) else { return }
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page),
            "variant",
            String(variant.quality),
            source.identity
        ].joined(separator: "|")
        scheduleMediaWarmup(
            source,
            bvid: bvid,
            key: key,
            delay: delay
        )
    }

    @discardableResult
    func warmVariantAroundSeek(
        _ variant: PlayVariant,
        bvid: String,
        cid: Int,
        page: Int?,
        playbackTime: TimeInterval,
        timeout: TimeInterval = 0.9
    ) async -> Bool {
        guard let source = PlayableMediaWarmupSource(variant: variant),
              playbackTime.isFinite,
              playbackTime > 0
        else { return false }
        let seekBucket = Int(max(0, playbackTime) / 30)
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page),
            "seek",
            String(seekBucket),
            String(variant.quality),
            source.identity
        ].joined(separator: "|")

        trimExpiredMediaWarmups()
        if mediaWarmupCache[key] != nil {
            return true
        }

        let warmupTask = Task(priority: .userInitiated) {
            await Self.warmPlayableMedia(source, bvid: bvid, around: playbackTime)
        }
        let timeoutTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return false
        }
        let didWarm = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { await warmupTask.value }
            group.addTask { await timeoutTask.value }
            let result = await group.next() ?? false
            group.cancelAll()
            warmupTask.cancel()
            timeoutTask.cancel()
            return result
        }
        if didWarm {
            mediaWarmupCache[key] = Date()
            trimMediaWarmupCacheIfNeeded()
        }
        return didWarm
    }

    @discardableResult
    func warmVariantsAroundSeek(
        _ variants: [PlayVariant],
        bvid: String,
        cid: Int,
        page: Int?,
        playbackTime: TimeInterval,
        timeout: TimeInterval = 0.9
    ) async -> Bool {
        guard playbackTime.isFinite, playbackTime > 0 else { return false }
        var seen = Set<String>()
        let sources = variants
            .compactMap(PlayableMediaWarmupSource.init(variant:))
            .filter { seen.insert($0.identity).inserted }
        guard !sources.isEmpty else { return false }
        let seekBucket = Int(max(0, playbackTime) / 30)
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page),
            "seekMerged",
            String(seekBucket),
            sources.map(\.identity).joined(separator: "||")
        ].joined(separator: "|")

        trimExpiredMediaWarmups()
        if mediaWarmupCache[key] != nil {
            return true
        }

        let warmupTask = Task(priority: .userInitiated) {
            await Self.warmPlayableMediaBatch(sources, bvid: bvid, around: playbackTime)
        }
        let timeoutTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return false
        }
        let didWarm = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { await warmupTask.value }
            group.addTask { await timeoutTask.value }
            let result = await group.next() ?? false
            group.cancelAll()
            warmupTask.cancel()
            timeoutTask.cancel()
            return result
        }
        if didWarm {
            mediaWarmupCache[key] = Date()
            trimMediaWarmupCacheIfNeeded()
        }
        return didWarm
    }

    func cancel(_ video: VideoItem) {
        guard let cid = video.cid else { return }
        let key = cacheKey(bvid: video.bvid, cid: cid, page: nil)
        tasks[key]?.cancel()
        tasks[key] = nil
        taskUserInitiatedFlags[key] = nil
        taskPreferredQualities[key] = nil
        activeOrder.removeAll { $0 == key }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        taskUserInitiatedFlags.removeAll()
        taskPreferredQualities.removeAll()
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
        detailTaskUserInitiatedFlags.removeAll()
        bvidPlayInfoTasks.values.forEach { $0.cancel() }
        bvidPlayInfoTasks.removeAll()
        bvidPlayInfoTaskPreferredQualities.removeAll()
        bvidPlayInfoCache.removeAll()
        cancelMediaWarmups(clearCache: true)
        activeOrder.removeAll()
    }

    func clearPlayURLCache() {
        playURLCache.removeAll()
        bvidPlayInfoCache.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        bvidPlayInfoTasks.values.forEach { $0.cancel() }
        bvidPlayInfoTasks.removeAll()
        taskUserInitiatedFlags.removeAll()
        taskPreferredQualities.removeAll()
        bvidPlayInfoTaskPreferredQualities.removeAll()
        activeOrder.removeAll()
    }

    func invalidatePlayURLCache(for bvid: String) {
        guard !bvid.isEmpty else { return }
        playURLCache = playURLCache.filter { !$0.key.hasPrefix("\(bvid)|") }
        bvidPlayInfoCache = bvidPlayInfoCache.filter { !$0.key.hasPrefix("\(bvid)|") }
        let taskKeys = tasks.keys.filter { $0.hasPrefix("\(bvid)|") }
        for key in taskKeys {
            tasks[key]?.cancel()
            tasks[key] = nil
            taskUserInitiatedFlags[key] = nil
            taskPreferredQualities[key] = nil
        }
        let bvidTaskKeys = bvidPlayInfoTasks.keys.filter { $0.hasPrefix("\(bvid)|") }
        for key in bvidTaskKeys {
            bvidPlayInfoTasks[key]?.cancel()
            bvidPlayInfoTasks[key] = nil
            bvidPlayInfoTaskPreferredQualities[key] = nil
        }
        activeOrder.removeAll { $0.hasPrefix("\(bvid)|") }
    }

    func cancelMediaWarmups(clearCache: Bool = false) {
        mediaWarmupTasks.values.forEach { $0.cancel() }
        mediaWarmupTasks.removeAll()
        if clearCache {
            mediaWarmupCache.removeAll()
            Task {
                await LocalHLSBridge.clearWarmupCache()
            }
        }
    }

    func cancelMediaWarmups(except video: VideoItem) {
        guard !video.bvid.isEmpty else {
            cancelMediaWarmups(clearCache: false)
            return
        }
        let keepPrefix = "\(video.bvid)|"
        let keepKey = video.cid.map { cacheKey(bvid: video.bvid, cid: $0, page: nil) }
        for (key, task) in mediaWarmupTasks where key != keepKey {
            guard !key.hasPrefix(keepPrefix) else { continue }
            task.cancel()
        }
        mediaWarmupTasks = mediaWarmupTasks.filter { key, _ in
            key == keepKey || key.hasPrefix(keepPrefix)
        }
    }

    func prioritizePlayback(for video: VideoItem) {
        guard !video.bvid.isEmpty else { return }
        focusedPlaybackBVID = video.bvid
        focusedPlaybackUntil = Date().addingTimeInterval(5)
        let keepPrefix = "\(video.bvid)|"
        let keepKey = video.cid.map { cacheKey(bvid: video.bvid, cid: $0, page: nil) }

        for (key, task) in tasks {
            guard key == keepKey || key.hasPrefix(keepPrefix) else {
                task.cancel()
                tasks[key] = nil
                taskUserInitiatedFlags[key] = nil
                taskPreferredQualities[key] = nil
                activeOrder.removeAll { $0 == key }
                continue
            }
        }

        for (key, task) in detailTasks where key != video.bvid {
            task.cancel()
            detailTasks[key] = nil
            detailTaskUserInitiatedFlags[key] = nil
        }

        cancelMediaWarmups(clearCache: false)
    }

    private func shouldAllowPreload(bvid: String, priority: TaskPriority) -> Bool {
        guard priority != .userInitiated,
              let focusedPlaybackBVID,
              let focusedPlaybackUntil
        else { return true }

        if Date() >= focusedPlaybackUntil {
            self.focusedPlaybackBVID = nil
            self.focusedPlaybackUntil = nil
            return true
        }

        return bvid == focusedPlaybackBVID
    }

    private func finish(_ key: String) {
        tasks[key] = nil
        taskUserInitiatedFlags[key] = nil
        taskPreferredQualities[key] = nil
        activeOrder.removeAll { $0 == key }
    }

    private func finishDetail(_ bvid: String) {
        detailTasks[bvid] = nil
        detailTaskUserInitiatedFlags[bvid] = nil
    }

    private func finishBVIDPlayInfo(_ key: String) {
        bvidPlayInfoTasks[key] = nil
        bvidPlayInfoTaskPreferredQualities[key] = nil
    }

    private func finishMediaWarmup(_ key: String, didWarm: Bool) {
        mediaWarmupTasks[key] = nil
        if didWarm {
            mediaWarmupCache[key] = Date()
        }
        trimMediaWarmupCacheIfNeeded()
    }

    private func waitForCachedPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int?,
        timeout nanoseconds: UInt64
    ) async -> PlayURLData? {
        var remaining = nanoseconds
        let tick = min(80_000_000, nanoseconds)
        while remaining > 0 {
            if let cached = cachedPlayURL(for: bvid, cid: cid, page: page, preferredQuality: preferredQuality) {
                return cached
            }
            let sleepDuration = min(tick, remaining)
            try? await Task.sleep(nanoseconds: sleepDuration)
            remaining -= sleepDuration
        }
        return cachedPlayURL(for: bvid, cid: cid, page: page, preferredQuality: preferredQuality)
    }

    private func waitForCachedBVIDPlayInfo(
        bvid: String,
        preferredQuality: Int?,
        timeout nanoseconds: UInt64
    ) async -> PlayURLData? {
        var remaining = nanoseconds
        let tick = min(80_000_000, nanoseconds)
        while remaining > 0 {
            for key in bvidPlayInfoKeys(bvid: bvid, preferredQuality: preferredQuality) {
                if let cached = bvidPlayInfoCache[key] {
                    return cached.data
                }
            }
            let sleepDuration = min(tick, remaining)
            try? await Task.sleep(nanoseconds: sleepDuration)
            remaining -= sleepDuration
        }
        for key in bvidPlayInfoKeys(bvid: bvid, preferredQuality: preferredQuality) {
            if let cached = bvidPlayInfoCache[key] {
                return cached.data
            }
        }
        return nil
    }

    private func trimIfNeeded() {
        while activeOrder.count >= maxConcurrentPreloads, let oldest = activeOrder.first {
            tasks[oldest]?.cancel()
            tasks[oldest] = nil
            taskUserInitiatedFlags[oldest] = nil
            taskPreferredQualities[oldest] = nil
            activeOrder.removeFirst()
        }
    }

    private func cacheKey(bvid: String, cid: Int, page: Int?, preferredQuality: Int? = nil) -> String {
        "\(bvid)|\(cid)|\(normalizedPage(page) ?? 0)|q\(preferredQuality ?? 0)"
    }

    private func normalizedPage(_ page: Int?) -> Int? {
        guard let page, page > 1 else { return nil }
        return page
    }

    private func bvidPlayInfoKey(bvid: String, preferredQuality: Int?) -> String {
        "\(bvid)|webpage|q\(preferredQuality ?? 0)"
    }

    private func bvidPlayInfoKeys(bvid: String, preferredQuality: Int?) -> [String] {
        let keys = [
            bvidPlayInfoKey(bvid: bvid, preferredQuality: preferredQuality),
            bvidPlayInfoKey(bvid: bvid, preferredQuality: nil)
        ]
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func pendingCacheKeys(bvid: String, cid: Int, page: Int?, preferredQuality: Int?) -> [String] {
        var keys = [
            cacheKey(bvid: bvid, cid: cid, page: page, preferredQuality: preferredQuality),
            cacheKey(bvid: bvid, cid: cid, page: page)
        ]
        if page != nil {
            keys.append(cacheKey(bvid: bvid, cid: cid, page: nil, preferredQuality: preferredQuality))
            keys.append(cacheKey(bvid: bvid, cid: cid, page: nil))
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func scheduleMediaWarmup(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        preferredQuality: Int?,
        page: Int?,
        cdnPreference: PlaybackCDNPreference,
        delay: TimeInterval = 0
    ) {
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page, preferredQuality: preferredQuality),
            "cdn",
            cdnPreference.rawValue
        ].joined(separator: "|")
        trimExpiredMediaWarmups()
        guard mediaWarmupTasks[key] == nil, mediaWarmupCache[key] == nil else { return }

        let priority: TaskPriority = delay <= 0 ? .userInitiated : .utility
        mediaWarmupTasks[key] = Task(priority: priority) {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                self.finishMediaWarmup(key, didWarm: false)
                return
            }
            let didWarm = await Self.warmPlayableMedia(
                data,
                bvid: bvid,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference
            )
            self.finishMediaWarmup(key, didWarm: didWarm)
        }
    }

    private func scheduleStartupPackageWarmup(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        preferredQuality: Int?,
        targetPreferredQuality: Int?,
        page: Int?,
        cdnPreference: PlaybackCDNPreference,
        mediaWarmupMode: VideoPreloadMediaWarmupMode,
        delay: TimeInterval = 0
    ) {
        let routePlanOnly = mediaWarmupMode.isRoutePlanOnly || shouldUseRoutePlanOnlyStartupWarmup(for: bvid)
        let key = [
            cacheKey(bvid: bvid, cid: cid, page: page, preferredQuality: preferredQuality),
            routePlanOnly ? "startupRoutePlan" : "startupPackage",
            "targetq\(targetPreferredQuality ?? 0)",
            cdnPreference.rawValue
        ].joined(separator: "|")
        trimExpiredMediaWarmups()
        guard mediaWarmupTasks[key] == nil, mediaWarmupCache[key] == nil else { return }

        let priority: TaskPriority = delay <= 0 ? .userInitiated : .utility
        PlayerMetricsLog.logger.info(
            "playInfoStartupWarmupScheduled bvid=\(bvid, privacy: .public) mode=\(routePlanOnly ? "routePlanOnly" : "full", privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public) target=\(targetPreferredQuality ?? 0, privacy: .public) delayMs=\(Int((delay * 1000).rounded()), privacy: .public)"
        )
        mediaWarmupTasks[key] = Task(priority: priority) {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                self.finishMediaWarmup(key, didWarm: false)
                return
            }
            let didPrebuild = await Self.prebuildPlayableManifest(
                data,
                bvid: bvid,
                preferredQuality: preferredQuality,
                targetPreferredQuality: targetPreferredQuality,
                cdnPreference: cdnPreference
            )
            let didWarmRanges: Bool
            if routePlanOnly {
                didWarmRanges = false
            } else {
                didWarmRanges = await Self.warmPlayableMedia(
                    data,
                    bvid: bvid,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference
                )
            }
            await PlayerMetricsLog.record(
                .manifestStage,
                metricsID: bvid,
                message: "startupPackage routePlan=\(didPrebuild ? "ready" : "skip") ranges=\(routePlanOnly ? "deferred" : (didWarmRanges ? "ready" : "skip"))"
            )
            PlayerMetricsLog.logger.info(
                "playInfoStartupWarmupComplete bvid=\(bvid, privacy: .public) mode=\(routePlanOnly ? "routePlanOnly" : "full", privacy: .public) routePlan=\(didPrebuild ? "ready" : "skip", privacy: .public) ranges=\(routePlanOnly ? "deferred" : (didWarmRanges ? "ready" : "skip"), privacy: .public)"
            )
            self.finishMediaWarmup(key, didWarm: didPrebuild || didWarmRanges)
        }
    }

    private func shouldUseRoutePlanOnlyStartupWarmup(for bvid: String) -> Bool {
        guard focusedPlaybackBVID == bvid,
              let focusedPlaybackUntil
        else { return false }
        if Date() < focusedPlaybackUntil {
            return true
        }
        self.focusedPlaybackBVID = nil
        self.focusedPlaybackUntil = nil
        return false
    }

    private func scheduleMediaWarmup(
        _ source: PlayableMediaWarmupSource,
        bvid: String,
        key: String,
        delay: TimeInterval = 0
    ) {
        trimExpiredMediaWarmups()
        guard mediaWarmupTasks[key] == nil, mediaWarmupCache[key] == nil else { return }

        let priority: TaskPriority = delay <= 0 ? .userInitiated : .utility
        mediaWarmupTasks[key] = Task(priority: priority) {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else {
                self.finishMediaWarmup(key, didWarm: false)
                return
            }
            let didWarm = await Self.warmPlayableMedia(source, bvid: bvid)
            self.finishMediaWarmup(key, didWarm: didWarm)
        }
    }

    private func trimExpiredPlayURLs(allowStalePlayable: Bool = false) {
        let ttl = allowStalePlayable ? stalePlayablePlayURLTTL : cachedPlayURLTTL
        let now = Date()
        let expiry = now.addingTimeInterval(-ttl)
        playURLCache = playURLCache.filter {
            $0.value.date >= expiry
                && PlayURLMediaExpiration.isReusable(expirationDate: $0.value.expiresAt, now: now)
        }
    }

    private func trimPlayURLCacheIfNeeded() {
        trimExpiredPlayURLs()
        guard playURLCache.count > maxCachedPlayURLCount else { return }
        let keptKeys = Set(
            playURLCache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCachedPlayURLCount)
                .map(\.key)
        )
        playURLCache = playURLCache.filter { keptKeys.contains($0.key) }
    }

    private func trimExpiredBVIDPlayInfo() {
        let now = Date()
        let expiry = now.addingTimeInterval(-cachedPlayURLTTL)
        bvidPlayInfoCache = bvidPlayInfoCache.filter {
            $0.value.date >= expiry
                && PlayURLMediaExpiration.isReusable(expirationDate: $0.value.expiresAt, now: now)
        }
    }

    private func trimBVIDPlayInfoCacheIfNeeded() {
        trimExpiredBVIDPlayInfo()
        guard bvidPlayInfoCache.count > maxCachedPlayURLCount else { return }
        let keptKeys = Set(
            bvidPlayInfoCache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCachedPlayURLCount)
                .map(\.key)
        )
        bvidPlayInfoCache = bvidPlayInfoCache.filter { keptKeys.contains($0.key) }
    }

    private struct CachedPlayURL {
        let data: PlayURLData
        let date: Date
        let expiresAt: Date
    }

    private func storeBVIDPlayInfo(_ data: PlayURLData, for key: String) {
        let now = Date()
        let expiresAt = PlayURLMediaExpiration.expirationDate(for: data, storedAt: now, fallbackTTL: cachedPlayURLTTL)
        guard PlayURLMediaExpiration.isReusable(expirationDate: expiresAt, now: now) else { return }
        bvidPlayInfoCache[key] = CachedPlayURL(data: data, date: now, expiresAt: expiresAt)
    }

    private func trimExpiredDetails() {
        let expiry = Date().addingTimeInterval(-cachedDetailTTL)
        detailCache = detailCache.filter { $0.value.date >= expiry }
    }

    private func trimDetailCacheIfNeeded() {
        trimExpiredDetails()
        guard detailCache.count > maxCachedDetailCount else { return }
        let keptKeys = Set(
            detailCache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCachedDetailCount)
                .map(\.key)
        )
        detailCache = detailCache.filter { keptKeys.contains($0.key) }
    }

    private func finishRelated(_ bvid: String) {
        relatedTasks[bvid] = nil
    }

    private func rememberRelatedCandidates(_ videos: [VideoItem], excluding bvid: String) {
        var merged = videos.filter { !$0.bvid.isEmpty && $0.bvid != bvid } + recentRelatedCandidates
        var seen = Set<String>()
        merged = merged.filter { video in
            seen.insert(video.bvid).inserted
        }
        recentRelatedCandidates = Array(merged.prefix(24))
    }

    private func trimExpiredRelated() {
        let expiry = Date().addingTimeInterval(-cachedRelatedTTL)
        relatedCache = relatedCache.filter { $0.value.date >= expiry }
        let cachedBVIDs = Set(relatedCache.values.flatMap { $0.videos.map(\.bvid) })
        recentRelatedCandidates = recentRelatedCandidates.filter { cachedBVIDs.contains($0.bvid) }
    }

    private func trimRelatedCacheIfNeeded() {
        trimExpiredRelated()
        guard relatedCache.count > maxCachedRelatedCount else { return }
        let keptKeys = Set(
            relatedCache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCachedRelatedCount)
                .map(\.key)
        )
        relatedCache = relatedCache.filter { keptKeys.contains($0.key) }
        let cachedBVIDs = Set(relatedCache.values.flatMap { $0.videos.map(\.bvid) })
        recentRelatedCandidates = recentRelatedCandidates.filter { cachedBVIDs.contains($0.bvid) }
    }

    private func trimExpiredMediaWarmups() {
        let expiry = Date().addingTimeInterval(-mediaWarmupTTL)
        mediaWarmupCache = mediaWarmupCache.filter { $0.value >= expiry }
    }

    private func trimMediaWarmupCacheIfNeeded() {
        trimExpiredMediaWarmups()
        guard mediaWarmupCache.count > maxMediaWarmupCount else { return }
        let keptKeys = Set(
            mediaWarmupCache
                .sorted { $0.value > $1.value }
                .prefix(maxMediaWarmupCount)
                .map(\.key)
        )
        mediaWarmupCache = mediaWarmupCache.filter { keptKeys.contains($0.key) }
    }

    private struct CachedVideoDetail {
        let detail: VideoItem
        let date: Date
    }

    private struct CachedRelatedVideos {
        let videos: [VideoItem]
        let date: Date
    }

    private nonisolated static func warmAsset(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        _ = try? await asset.load(.duration)
        return playable
    }

    private nonisolated static func warmPlayableMedia(
        _ data: PlayURLData,
        bvid: String,
        preferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference
    ) async -> Bool {
        let media: (
            videoURL: URL,
            audioURL: URL?,
            videoTrack: DASHStream?,
            audioTrack: DASHStream?,
            dynamicRange: BiliVideoDynamicRange
        )? = await MainActor.run {
            guard let variant = preferredPlayableVariant(
                in: data.playVariants(cdnPreference: cdnPreference),
                preferredQuality: preferredQuality
            ),
                  let videoURL = variant.videoURL
            else { return nil }
            return (videoURL, variant.audioURL, variant.videoStream, variant.audioStream, variant.dynamicRange)
        }
        guard let media else { return false }
        return await warmPlayableMedia(
            PlayableMediaWarmupSource(
                videoURL: media.videoURL,
                audioURL: media.audioURL,
                videoTrack: media.videoTrack,
                audioTrack: media.audioTrack,
                dynamicRange: media.dynamicRange
            ),
            bvid: bvid,
            cdnPreference: cdnPreference
        )
    }

    private nonisolated static func prebuildPlayableManifest(
        _ data: PlayURLData,
        bvid: String,
        preferredQuality: Int?,
        targetPreferredQuality: Int?,
        cdnPreference: PlaybackCDNPreference
    ) async -> Bool {
        let variants = data.playVariants(cdnPreference: cdnPreference)
        guard let startupVariant = preferredPlayableVariant(
            in: variants,
            preferredQuality: preferredQuality
        ),
              let source = PlayableMediaWarmupSource(variant: startupVariant)
        else { return false }
        let targetVariant = preferredPlayableVariant(
            in: variants,
            preferredQuality: targetPreferredQuality
        )
        let alternateSources = startupRoutePlanAlternateSources(
            startupVariant: startupVariant,
            targetVariant: targetVariant,
            variants: variants
        )
        let durationHint = data.dash?.duration.map(TimeInterval.init)
        return await prebuildPlayableManifest(
            source,
            alternateSources: alternateSources,
            bvid: bvid,
            durationHint: durationHint,
            cdnPreference: cdnPreference
        )
    }

    private nonisolated static func prebuildPlayableManifest(
        _ source: PlayableMediaWarmupSource,
        alternateSources: [PlayableMediaWarmupSource] = [],
        bvid: String,
        durationHint: TimeInterval?,
        cdnPreference: PlaybackCDNPreference
    ) async -> Bool {
        guard source.videoTrack != nil,
              let audioTrack = source.audioTrack,
              let audioURL = source.audioURL
        else { return false }
        var seenVideoURLs = Set<String>()
        let videoTracks = ([source] + alternateSources).compactMap { source -> HLSBridgeTrack? in
            guard let videoTrack = source.videoTrack,
                  seenVideoURLs.insert(source.videoURL.absoluteString).inserted
            else { return nil }
            return HLSBridgeTrack(
                url: source.videoURL,
                fallbackURLs: videoTrack.backupPlayURLs(cdnPreference: cdnPreference),
                stream: videoTrack,
                mediaType: .video,
                dynamicRange: source.dynamicRange
            )
        }
        guard !videoTracks.isEmpty else { return false }
        return await LocalHLSBridge.prebuildRoutePlan(
            videoTracks: videoTracks,
            audioTrack: HLSBridgeTrack(
                url: audioURL,
                fallbackURLs: audioTrack.backupPlayURLs(cdnPreference: cdnPreference),
                stream: audioTrack,
                mediaType: .audio
            ),
            durationHint: durationHint,
            headers: Self.httpHeaders(referer: "https://www.bilibili.com/video/\(bvid)"),
            metricsID: bvid
        )
    }

    private nonisolated static func startupRoutePlanAlternateSources(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant?,
        variants: [PlayVariant]
    ) -> [PlayableMediaWarmupSource] {
        let limit = startupRoutePlanAlternateLimit
        guard limit > 0,
              shouldPrebuildStartupRouteAlternates(from: startupVariant, to: targetVariant),
              let targetVariant
        else { return [] }
        let candidates = sortedPlayableVariants(variants)
            .filter { isStartupRouteAlternate($0, forStartupVariant: startupVariant) }
        guard !candidates.isEmpty else { return [] }

        var selected = [PlayVariant]()
        var seen = Set<String>()
        func append(_ variant: PlayVariant?) {
            guard selected.count < limit,
                  let variant,
                  seen.insert(variant.id).inserted
            else { return }
            selected.append(variant)
        }

        if isStartupRouteAlternate(targetVariant, forStartupVariant: startupVariant) {
            append(targetVariant)
        }
        for quality in startupRouteAlternateQualityOrder(targetQuality: targetVariant.quality) {
            append(candidates.first { $0.quality == quality })
        }
        for candidate in candidates {
            append(candidate)
        }
        return selected.compactMap(PlayableMediaWarmupSource.init(variant:))
    }

    private nonisolated static var startupRoutePlanAlternateLimit: Int {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return 0 }
        switch environment.networkClass {
        case .wifi:
            return 3
        case .unknown:
            return 2
        case .cellular, .constrained:
            return 0
        }
    }

    private nonisolated static func shouldPrebuildStartupRouteAlternates(
        from startupVariant: PlayVariant,
        to targetVariant: PlayVariant?
    ) -> Bool {
        guard let targetVariant,
              startupVariant.isPlayable,
              targetVariant.isPlayable,
              startupVariant.id != targetVariant.id,
              startupVariant.audioURL == targetVariant.audioURL,
              targetVariant.audioURL != nil,
              targetVariant.videoStream?.isHardwareDecodingCompatibleVideo == true,
              targetVariant.dynamicRange == .sdr,
              targetVariant.quality >= 74,
              variant(targetVariant, isBetterThan: startupVariant)
        else { return false }
        return true
    }

    private nonisolated static func isStartupRouteAlternate(
        _ variant: PlayVariant,
        forStartupVariant startupVariant: PlayVariant
    ) -> Bool {
        variant.isPlayable
            && variant.id != startupVariant.id
            && variant.audioURL == startupVariant.audioURL
            && variant.dynamicRange == startupVariant.dynamicRange
            && variant.videoStream?.isHardwareDecodingCompatibleVideo == true
            && variant.videoURL != nil
            && variantsShareVideoCodecFamily(variant, startupVariant)
            && variantsShareStartupFrameRateClass(variant, startupVariant)
    }

    private nonisolated static func startupRouteAlternateQualityOrder(targetQuality: Int) -> [Int] {
        var qualities = [Int]()
        func append(_ quality: Int) {
            guard !qualities.contains(quality) else { return }
            qualities.append(quality)
        }
        append(targetQuality)
        [112, 80, 64, 32].forEach(append)
        return qualities
    }

    private nonisolated static func warmPlayableMedia(
        _ source: PlayableMediaWarmupSource,
        bvid: String,
        around playbackTime: TimeInterval? = nil,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) async -> Bool {
        let videoURL = source.videoURL
        if let videoTrack = source.videoTrack {
            let audioTrack = source.audioTrack.flatMap { track -> HLSBridgeTrack? in
                guard let audioURL = source.audioURL else { return nil }
                return HLSBridgeTrack(
                    url: audioURL,
                    fallbackURLs: track.backupPlayURLs(cdnPreference: cdnPreference),
                    stream: track,
                    mediaType: .audio
                )
            }
            return await LocalHLSBridge.warmup(
                videoTrack: HLSBridgeTrack(
                    url: videoURL,
                    fallbackURLs: videoTrack.backupPlayURLs(cdnPreference: cdnPreference),
                    stream: videoTrack,
                    mediaType: .video,
                    dynamicRange: source.dynamicRange
                ),
                audioTrack: audioTrack,
                headers: Self.httpHeaders(referer: "https://www.bilibili.com/video/\(bvid)"),
                around: playbackTime
            )
        } else {
            async let videoAssetWarmup: Bool = warmAsset(url: videoURL)
            if let audioURL = source.audioURL {
                async let audioAssetWarmup: Bool = warmAsset(url: audioURL)
                let results = await (videoAssetWarmup, audioAssetWarmup)
                return results.0 || results.1
            } else {
                return await videoAssetWarmup
            }
        }
    }

    private nonisolated static func warmPlayableMediaBatch(
        _ sources: [PlayableMediaWarmupSource],
        bvid: String,
        around playbackTime: TimeInterval?,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) async -> Bool {
        var seenVideoTracks = Set<String>()
        let videoTracks = sources.compactMap { source -> HLSBridgeTrack? in
            guard let videoTrack = source.videoTrack,
                  seenVideoTracks.insert(source.videoURL.absoluteString).inserted
            else { return nil }
            return HLSBridgeTrack(
                url: source.videoURL,
                fallbackURLs: videoTrack.backupPlayURLs(cdnPreference: cdnPreference),
                stream: videoTrack,
                mediaType: .video,
                dynamicRange: source.dynamicRange
            )
        }
        let audioTrack = sources.lazy.compactMap { source -> HLSBridgeTrack? in
            guard let audioTrack = source.audioTrack,
                  let audioURL = source.audioURL
            else { return nil }
            return HLSBridgeTrack(
                url: audioURL,
                fallbackURLs: audioTrack.backupPlayURLs(cdnPreference: cdnPreference),
                stream: audioTrack,
                mediaType: .audio
            )
        }.first
        guard !videoTracks.isEmpty else {
            return await warmPlayableMedia(sources[0], bvid: bvid, around: playbackTime)
        }
        return await LocalHLSBridge.warmup(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            headers: Self.httpHeaders(referer: "https://www.bilibili.com/video/\(bvid)"),
            around: playbackTime
        )
    }

    private nonisolated static func preferredPlayableVariant(
        in variants: [PlayVariant],
        preferredQuality: Int?
    ) -> PlayVariant? {
        let playableVariants = sortedPlayableVariants(variants)

        if let preferredQuality {
            if let exact = playableVariants.first(where: { $0.quality == preferredQuality }) {
                return exact
            }
            let fallbackQualities = [112, 80, 116, 120, 74, 64, 32, 16, 6]
            for quality in fallbackQualities {
                if let variant = playableVariants.first(where: { $0.quality == quality }) {
                    return variant
                }
            }
        }

        let preferredQualities = PlaybackEnvironment.current.preferredQualityLadder
        for quality in preferredQualities {
            if let variant = playableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return playableVariants.first
    }

    private nonisolated static func sortedPlayableVariants(_ variants: [PlayVariant]) -> [PlayVariant] {
        variants
            .filter(\.isPlayable)
            .sorted { lhs, rhs in
                if lhs.isProgressiveFastStart != rhs.isProgressiveFastStart {
                    return !lhs.isProgressiveFastStart && rhs.isProgressiveFastStart
                }
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                let lhsFPS = playbackFrameRate(lhs)
                let rhsFPS = playbackFrameRate(rhs)
                if lhsFPS != rhsFPS {
                    return lhsFPS > rhsFPS
                }
                return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
            }
    }

    private nonisolated static func variant(_ candidate: PlayVariant, isBetterThan current: PlayVariant) -> Bool {
        if candidate.isProgressiveFastStart != current.isProgressiveFastStart {
            return !candidate.isProgressiveFastStart && current.isProgressiveFastStart
        }
        if candidate.quality != current.quality {
            return candidate.quality > current.quality
        }
        let candidateFPS = playbackFrameRate(candidate)
        let currentFPS = playbackFrameRate(current)
        if candidateFPS != currentFPS {
            return candidateFPS > currentFPS
        }
        return (candidate.bandwidth ?? 0) > (current.bandwidth ?? 0)
    }

    private nonisolated static func variantsShareStartupFrameRateClass(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        let lhsIsHighFrameRate = playbackFrameRate(lhs) >= 50
        let rhsIsHighFrameRate = playbackFrameRate(rhs) >= 50
        return lhsIsHighFrameRate == rhsIsHighFrameRate
    }

    private nonisolated static func variantsShareVideoCodecFamily(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        guard let lhsCodec = videoCodecFamily(lhs),
              let rhsCodec = videoCodecFamily(rhs)
        else {
            return true
        }
        return lhsCodec == rhsCodec
    }

    private nonisolated static func videoCodecFamily(_ variant: PlayVariant) -> String? {
        if let codecid = variant.videoStream?.codecid {
            switch codecid {
            case 7:
                return "avc"
            case 12:
                return "hevc"
            case 13:
                return "av1"
            default:
                break
            }
        }

        let codec = (variant.videoStream?.codecs ?? variant.codec ?? "").lowercased()
        if codec.contains("avc1") || codec.contains("avc3") {
            return "avc"
        }
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return "hevc"
        }
        if codec.contains("av01") {
            return "av1"
        }
        return nil
    }

    private nonisolated static func playbackFrameRate(_ variant: PlayVariant) -> Double {
        if let frameRate = DASHStream.numericFrameRate(from: variant.frameRate) {
            return frameRate
        }
        if [116, 74].contains(variant.quality) {
            return 60
        }
        if variant.title.contains("高帧")
            || variant.title.contains("60")
            || variant.badge?.contains("高帧") == true
            || variant.badge?.contains("60") == true {
            return 60
        }
        return 0
    }

    private nonisolated static func qualitySummary(_ variants: [PlayVariant]) -> String {
        let summary = variants
            .filter(\.isPlayable)
            .map { variant in
                let kind = variant.isProgressiveFastStart ? "p" : "d"
                return "\(variant.quality)\(kind)"
            }
            .joined(separator: ",")
        return summary.isEmpty ? "-" : summary
    }

    private nonisolated static func httpHeaders(referer: String) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
    }
}

nonisolated struct VideoRangeCacheStatistics: Sendable {
    let entryCount: Int
    let estimatedBytes: Int
    let byteCapacity: Int
}

actor VideoRangeCache {
    static let shared = VideoRangeCache()

    private struct CachedRangeEntry: Sendable {
        let range: HTTPByteRange
        let fileURL: URL
    }

    private struct PendingRangeEntry: Sendable {
        let range: HTTPByteRange
        let task: Task<Data, Error>
    }

    private enum PendingRangeError: Error {
        case invalidData
    }

    private let maxCacheBytes: Int64 = 512 * 1024 * 1024
    private let fileManager = FileManager.default
    private let rootURL: URL
    private var pendingFetches: [String: Task<Data, Error>] = [:]
    private var cachedRangesByURLHash: [String: [CachedRangeEntry]] = [:]
    private var pendingRangesByURLHash: [String: [PendingRangeEntry]] = [:]
    private var estimatedCacheBytes: Int64?
    private var storeCountSinceTrim = 0
    private var trimTask: Task<Void, Never>?

    init() {
        rootURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoRangeCache", isDirectory: true)
    }

    func data(url: URL, range: HTTPByteRange) -> Data? {
        let fileURL = cacheFileURL(url: url, range: range)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
        }
        return containingCachedData(url: url, range: range)
    }

    func cachedOrFetch(
        url: URL,
        range: HTTPByteRange,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let result = try await cachedOrFetchWithSource(url: url, range: range, loader: loader)
        return result.data
    }

    func cachedOrFetchWithSource(
        url: URL,
        range: HTTPByteRange,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> (data: Data, source: VideoRangeCacheFetchSource) {
        if let cached = data(url: url, range: range) {
            return (cached, .cache)
        }

        let key = cacheKey(url: url, range: range)
        if let pendingFetch = pendingFetches[key] {
            return (try await pendingFetch.value, .pending)
        }
        if let pendingFetch = containingPendingFetch(url: url, range: range) {
            return (try await pendingFetch.value, .pending)
        }

        let pendingFetch = Task.detached(priority: .userInitiated) {
            try await loader()
        }
        pendingFetches[key] = pendingFetch
        indexPendingRange(url: url, range: range, task: pendingFetch)

        do {
            let data = try await pendingFetch.value
            pendingFetches[key] = nil
            removePendingRange(url: url, range: range)
            store(data, url: url, range: range)
            return (data, .remote)
        } catch {
            pendingFetches[key] = nil
            removePendingRange(url: url, range: range)
            throw error
        }
    }

    func reserveExternalFetch(
        url: URL,
        range: HTTPByteRange,
        maxCacheBytes: Int64
    ) -> VideoRangeExternalFetchReservation {
        if let cached = data(url: url, range: range) {
            return .cached(cached)
        }
        let key = cacheKey(url: url, range: range)
        if let pendingFetch = pendingFetches[key] {
            return .pending(pendingFetch)
        }
        if let pendingFetch = containingPendingFetch(url: url, range: range) {
            return .pending(pendingFetch)
        }
        guard range.length <= maxCacheBytes else {
            return .unreserved
        }

        let completion = VideoRangePendingCompletion()
        let pendingFetch = Task.detached(priority: .userInitiated) {
            try await completion.value()
        }
        pendingFetches[key] = pendingFetch
        indexPendingRange(url: url, range: range, task: pendingFetch)
        return .reserved(VideoRangeExternalFetchToken(
            key: key,
            url: url,
            range: range,
            completion: completion
        ))
    }

    func finishExternalFetch(_ token: VideoRangeExternalFetchToken, data: Data) {
        guard pendingFetches[token.key] != nil else { return }
        pendingFetches[token.key] = nil
        removePendingRange(url: token.url, range: token.range)
        token.completion.succeed(data)
        store(data, url: token.url, range: token.range)
    }

    func failExternalFetch(_ token: VideoRangeExternalFetchToken, error: Error) {
        guard pendingFetches[token.key] != nil else { return }
        pendingFetches[token.key] = nil
        removePendingRange(url: token.url, range: token.range)
        token.completion.fail(error)
    }

    func store(_ data: Data, url: URL, range: HTTPByteRange) {
        guard !data.isEmpty else { return }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let fileURL = cacheFileURL(url: url, range: range)
            try data.write(to: fileURL, options: .atomic)
            indexCachedRange(url: url, range: range, fileURL: fileURL)
            estimatedCacheBytes = (estimatedCacheBytes ?? 0) + Int64(data.count)
            scheduleTrimIfNeeded()
            ResourceCacheAutoTrim.schedule()
        } catch {}
    }

    func statistics() -> VideoRangeCacheStatistics {
        let entries = cacheEntries()
        let totalSize = entries.reduce(Int64(0)) { $0 + $1.size }
        estimatedCacheBytes = totalSize
        return VideoRangeCacheStatistics(
            entryCount: entries.count,
            estimatedBytes: min(Int64(Int.max), totalSize).intValue,
            byteCapacity: min(Int64(Int.max), maxCacheBytes).intValue
        )
    }

    func clear() {
        trimTask?.cancel()
        trimTask = nil
        try? fileManager.removeItem(at: rootURL)
        cachedRangesByURLHash.removeAll(keepingCapacity: true)
        pendingRangesByURLHash.removeAll(keepingCapacity: true)
        estimatedCacheBytes = 0
        storeCountSinceTrim = 0
    }

    func trim(to targetBytes: Int64) {
        trimCache(to: max(0, targetBytes))
    }

    private func containingCachedData(url: URL, range: HTTPByteRange) -> Data? {
        guard range.length > 0 else { return nil }
        let urlHash = Self.stableCacheHash(url.absoluteString)
        guard let entries = cachedRangesByURLHash[urlHash], !entries.isEmpty else { return nil }
        let candidates = entries
            .filter {
                $0.range.start <= range.start
                    && $0.range.endInclusive >= range.endInclusive
            }
            .sorted { $0.range.length < $1.range.length }

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.fileURL.path),
                  let lowerBound = Int(exactly: range.start - candidate.range.start),
                  let length = Int(exactly: range.length),
                  length > 0
            else { continue }
            guard let cachedData = try? Data(contentsOf: candidate.fileURL, options: .mappedIfSafe),
                  lowerBound >= 0,
                  lowerBound + length <= cachedData.count
            else { continue }
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: candidate.fileURL.path)
            PlayerMetricsLog.logger.info(
                "videoRangeCacheSubrangeHit bytes=\(length, privacy: .public) sourceBytes=\(cachedData.count, privacy: .public)"
            )
            return cachedData.subdata(in: lowerBound..<(lowerBound + length))
        }
        return nil
    }

    private func containingPendingFetch(url: URL, range: HTTPByteRange) -> Task<Data, Error>? {
        guard range.length > 0 else { return nil }
        let urlHash = Self.stableCacheHash(url.absoluteString)
        guard let entries = pendingRangesByURLHash[urlHash], !entries.isEmpty else { return nil }
        let candidates = entries
            .filter {
                $0.range.start <= range.start
                    && $0.range.endInclusive >= range.endInclusive
            }
            .sorted { $0.range.length < $1.range.length }
        guard let candidate = candidates.first,
              let lowerBound = Int(exactly: range.start - candidate.range.start),
              let length = Int(exactly: range.length),
              length > 0
        else { return nil }

        let sourceTask = candidate.task
        return Task.detached(priority: .userInitiated) {
            let data = try await sourceTask.value
            guard lowerBound >= 0, lowerBound + length <= data.count else {
                throw PendingRangeError.invalidData
            }
            PlayerMetricsLog.logger.info(
                "videoRangeCachePendingSubrangeJoin bytes=\(length, privacy: .public) sourceBytes=\(data.count, privacy: .public)"
            )
            return data.subdata(in: lowerBound..<(lowerBound + length))
        }
    }

    private func indexCachedRange(url: URL, range: HTTPByteRange, fileURL: URL) {
        let urlHash = Self.stableCacheHash(url.absoluteString)
        var entries = cachedRangesByURLHash[urlHash] ?? []
        guard !entries.contains(where: { $0.range == range }) else { return }
        entries.append(CachedRangeEntry(range: range, fileURL: fileURL))
        if entries.count > 128 {
            entries.removeFirst(entries.count - 128)
        }
        cachedRangesByURLHash[urlHash] = entries
    }

    private func indexPendingRange(url: URL, range: HTTPByteRange, task: Task<Data, Error>) {
        let urlHash = Self.stableCacheHash(url.absoluteString)
        var entries = pendingRangesByURLHash[urlHash] ?? []
        entries.removeAll { $0.range == range }
        entries.append(PendingRangeEntry(range: range, task: task))
        if entries.count > 128 {
            entries.removeFirst(entries.count - 128)
        }
        pendingRangesByURLHash[urlHash] = entries
    }

    private func removePendingRange(url: URL, range: HTTPByteRange) {
        let urlHash = Self.stableCacheHash(url.absoluteString)
        guard var entries = pendingRangesByURLHash[urlHash] else { return }
        entries.removeAll { $0.range == range }
        if entries.isEmpty {
            pendingRangesByURLHash[urlHash] = nil
        } else {
            pendingRangesByURLHash[urlHash] = entries
        }
    }

    private func scheduleTrimIfNeeded() {
        storeCountSinceTrim += 1
        guard trimTask == nil else { return }
        guard storeCountSinceTrim >= 24 || (estimatedCacheBytes ?? 0) > maxCacheBytes + 64 * 1024 * 1024 else { return }
        trimTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.trimIfNeeded()
            self.trimTask = nil
        }
    }

    private func cacheFileURL(url: URL, range: HTTPByteRange) -> URL {
        rootURL.appendingPathComponent("\(cacheKey(url: url, range: range)).bin")
    }

    private func cacheKey(url: URL, range: HTTPByteRange) -> String {
        "\(Self.stableCacheHash(url.absoluteString))-\(range.start)-\(range.endInclusive)"
    }

    private nonisolated static func stableCacheHash(_ string: String) -> String {
        let basis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let value = string.utf8.reduce(basis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(value, radix: 16)
    }

    private func trimIfNeeded() {
        trimCache(to: maxCacheBytes)
    }

    private func trimCache(to targetBytes: Int64) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }

        var totalSize = entries.reduce(Int64(0)) { $0 + $1.size }
        estimatedCacheBytes = totalSize
        storeCountSinceTrim = 0
        guard totalSize > targetBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= targetBytes { break }
        }
        cachedRangesByURLHash.removeAll(keepingCapacity: true)
        pendingRangesByURLHash.removeAll(keepingCapacity: true)
        estimatedCacheBytes = totalSize
    }

    private func cacheEntries() -> [(url: URL, date: Date, size: Int64)] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }

        return files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
    }
}

private extension Int64 {
    var intValue: Int {
        Int(self)
    }
}

enum VideoRangeExternalFetchReservation: Sendable {
    case cached(Data)
    case pending(Task<Data, Error>)
    case reserved(VideoRangeExternalFetchToken)
    case unreserved
}

nonisolated enum VideoRangeCacheFetchSource: Sendable, Equatable {
    case cache
    case pending
    case remote
}

struct VideoRangeExternalFetchToken: Sendable {
    let key: String
    let url: URL
    let range: HTTPByteRange
    let completion: VideoRangePendingCompletion
}

nonisolated final class VideoRangePendingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?

    func value() async throws -> Data {
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

    func succeed(_ data: Data) {
        complete(.success(data))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Data, Error>) {
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

private struct PlayableMediaWarmupSource: Sendable {
    let videoURL: URL
    let audioURL: URL?
    let videoTrack: DASHStream?
    let audioTrack: DASHStream?
    let dynamicRange: BiliVideoDynamicRange

    nonisolated var identity: String {
        [
            videoURL.absoluteString,
            audioURL?.absoluteString ?? "",
            "\(videoTrack?.id ?? 0)",
            "\(videoTrack?.bandwidth ?? 0)",
            videoTrack?.codecs ?? "",
            "\(audioTrack?.bandwidth ?? 0)",
            dynamicRange.rawValue
        ].joined(separator: "|")
    }

    nonisolated init?(variant: PlayVariant) {
        guard let videoURL = variant.videoURL else { return nil }
        self.init(
            videoURL: videoURL,
            audioURL: variant.audioURL,
            videoTrack: variant.videoStream,
            audioTrack: variant.audioStream,
            dynamicRange: variant.dynamicRange
        )
    }

    nonisolated init(
        videoURL: URL,
        audioURL: URL?,
        videoTrack: DASHStream?,
        audioTrack: DASHStream?,
        dynamicRange: BiliVideoDynamicRange = .sdr
    ) {
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.videoTrack = videoTrack
        self.audioTrack = audioTrack
        self.dynamicRange = dynamicRange
    }
}

@MainActor
enum Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

nonisolated enum RemoteImageCachePolicy: Hashable, Sendable {
    case standard
    case reloadIgnoringLocalCacheData

    var requestCachePolicy: URLRequest.CachePolicy {
        switch self {
        case .standard:
            return .returnCacheDataElseLoad
        case .reloadIgnoringLocalCacheData:
            return .reloadIgnoringLocalCacheData
        }
    }
}

nonisolated struct RemoteImageSource: Hashable, Sendable {
    let url: URL
    let fallbackURL: URL?

    init(url: URL, fallbackURL: URL? = nil) {
        self.url = url
        self.fallbackURL = fallbackURL
    }

    var urls: [URL] {
        uniqueRemoteImageURLs([url, fallbackURL])
    }
}

enum RemoteImageLoadingPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let fallbackURL: URL?
    let scale: CGFloat
    let targetPixelSize: Int?
    let cachePolicy: RemoteImageCachePolicy
    let animatesAppearance: Bool
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: (RemoteImageLoadingPhase, @escaping () -> Void) -> Placeholder

    @StateObject private var loader = CachedRemoteImageLoader()
    @State private var reloadToken = 0
    @State private var automaticRetryTask: Task<Void, Never>?

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        scale: CGFloat = 1,
        targetPixelSize: Int? = nil,
        cachePolicy: RemoteImageCachePolicy = .standard,
        animatesAppearance: Bool = true,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.scale = scale
        self.targetPixelSize = targetPixelSize
        self.cachePolicy = cachePolicy
        self.animatesAppearance = animatesAppearance
        self.content = content
        self.placeholder = { _, _ in placeholder() }
    }

    init(
        url: URL?,
        fallbackURL: URL? = nil,
        scale: CGFloat = 1,
        targetPixelSize: Int? = nil,
        cachePolicy: RemoteImageCachePolicy = .standard,
        animatesAppearance: Bool = true,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder phasePlaceholder: @escaping (RemoteImageLoadingPhase, @escaping () -> Void) -> Placeholder
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.scale = scale
        self.targetPixelSize = targetPixelSize
        self.cachePolicy = cachePolicy
        self.animatesAppearance = animatesAppearance
        self.content = content
        self.placeholder = phasePlaceholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(uiImage: image))
                    .transition(animatesAppearance ? .opacity : .identity)
            } else {
                placeholder(loader.phase, retry)
            }
        }
        .animation(animatesAppearance ? .easeInOut(duration: 0.16) : nil, value: loader.image != nil)
        .onChange(of: loader.phase) { _, phase in
            scheduleAutomaticRetryIfNeeded(for: phase)
        }
        .task(id: loadTaskIdentity) {
            await loader.load(
                url: url,
                fallbackURL: fallbackURL,
                scale: scale,
                targetPixelSize: targetPixelSize,
                cachePolicy: cachePolicy,
                clearsFailedMarkers: reloadToken > 0
            )
        }
        .onDisappear {
            automaticRetryTask?.cancel()
            automaticRetryTask = nil
            loader.cancel()
            if loader.image == nil {
                loader.reset()
            }
        }
    }

    private var cacheIdentity: String {
        uniqueRemoteImageURLs([url, fallbackURL])
            .map(\.absoluteString)
            .joined(separator: "|") + "|\(targetPixelSize ?? 0)|\(scale)|\(cachePolicy)"
    }

    private var loadTaskIdentity: String {
        "\(cacheIdentity)|reload:\(reloadToken)"
    }

    private func retry() {
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
        loader.reset()
        reloadToken &+= 1
    }

    private func scheduleAutomaticRetryIfNeeded(for phase: RemoteImageLoadingPhase) {
        guard phase == .failed,
              reloadToken == 0,
              automaticRetryTask == nil
        else {
            if phase != .failed {
                automaticRetryTask?.cancel()
                automaticRetryTask = nil
            }
            return
        }
        automaticRetryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            loader.reset()
            reloadToken &+= 1
            automaticRetryTask = nil
        }
    }
}

struct AvatarRemoteImage<Placeholder: View>: View {
    let urlString: String?
    let pixelSize: Int
    let animatesAppearance: Bool
    @ViewBuilder let placeholder: () -> Placeholder

    init(
        urlString: String?,
        pixelSize: Int,
        animatesAppearance: Bool = false,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urlString = urlString
        self.pixelSize = pixelSize
        self.animatesAppearance = animatesAppearance
        self.placeholder = placeholder
    }

    var body: some View {
        CachedRemoteImage(
            url: thumbnailURL,
            fallbackURL: sourceURL,
            targetPixelSize: pixelSize,
            animatesAppearance: animatesAppearance
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder()
        }
    }

    private var normalizedURLString: String? {
        urlString?.normalizedBiliURL()
    }

    private var sourceURL: URL? {
        normalizedURLString.flatMap(URL.init(string:))
    }

    private var thumbnailURL: URL? {
        normalizedURLString
            .map { $0.biliAvatarThumbnailURL(size: pixelSize) }
            .flatMap(URL.init(string:))
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var phase: RemoteImageLoadingPhase = .idle
    private var task: Task<Void, Never>?
    private var loadIdentity: String?
    private var imageIdentity: String?

    func load(
        url: URL?,
        fallbackURL: URL? = nil,
        scale: CGFloat,
        targetPixelSize: Int?,
        cachePolicy: RemoteImageCachePolicy = .standard,
        clearsFailedMarkers: Bool = false
    ) async {
        let urls = uniqueRemoteImageURLs([url, fallbackURL])
        guard !urls.isEmpty else {
            task?.cancel()
            task = nil
            loadIdentity = nil
            imageIdentity = nil
            image = nil
            phase = .idle
            return
        }
        let identity = urls.map(\.absoluteString).joined(separator: "|") + "|\(targetPixelSize ?? 0)|\(scale)|\(cachePolicy)"

        if loadIdentity == identity, imageIdentity == identity, image != nil {
            phase = .loaded
            return
        }
        if loadIdentity == identity, let task {
            await task.value
            return
        }

        task?.cancel()
        loadIdentity = identity
        if imageIdentity != identity {
            image = nil
            imageIdentity = nil
        }
        phase = .loading

        if clearsFailedMarkers {
            for candidateURL in urls {
                await RemoteImageCache.shared.clearFailure(
                    for: candidateURL,
                    scale: scale,
                    targetPixelSize: targetPixelSize
                )
            }
        }

        if cachePolicy == .standard {
            for candidateURL in urls {
                if let cachedImage = await RemoteImageCache.shared.image(for: candidateURL, scale: scale, targetPixelSize: targetPixelSize) {
                    guard loadIdentity == identity else { return }
                    image = cachedImage
                    imageIdentity = identity
                    phase = .loaded
                    task = nil
                    return
                }
            }
        }

        task = Task(priority: .utility) { [weak self, identity, urls, cachePolicy] in
            for candidateURL in urls {
                guard !Task.isCancelled else { return }
                let loadedImage = await RemoteImageCache.shared.load(
                    url: candidateURL,
                    scale: scale,
                    targetPixelSize: targetPixelSize,
                    cachePolicy: cachePolicy
                )
                guard !Task.isCancelled else { return }
                guard let loadedImage else { continue }
                await MainActor.run {
                    guard self?.loadIdentity == identity else { return }
                    self?.image = loadedImage
                    self?.imageIdentity = identity
                    self?.phase = .loaded
                    self?.task = nil
                }
                return
            }

            await MainActor.run {
                guard self?.loadIdentity == identity else { return }
                self?.phase = .failed
                self?.task = nil
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        task?.cancel()
        task = nil
        loadIdentity = nil
        imageIdentity = nil
        image = nil
        phase = .idle
    }
}

nonisolated private func uniqueRemoteImageURLs(_ urls: [URL?]) -> [URL] {
    var seen = Set<String>()
    return urls.compactMap { url in
        guard let url else { return nil }
        return seen.insert(url.absoluteString).inserted ? url : nil
    }
}

actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [ImageCacheKey: Task<UIImage?, Never>] = [:]
    private var inFlightOrder: [ImageCacheKey] = []
    private var diskRequests: [ImageCacheKey: DiskRequestEntry] = [:]
    private var storedKeys = Set<ImageCacheKey>()
    private var hits = 0
    private var misses = 0
    private var stores = 0
    private var evictions = 0
    private var failedLoads: [ImageCacheKey: Date] = [:]
    private var appliedBudget: RemoteImageAdaptiveBudget?
    private var diskTrimTask: Task<Void, Never>?
    private var session: URLSession
    private let maximumInFlightLoads = 18
    private let failedLoadTTL: TimeInterval = 2
    private let diskTrimDelayNanoseconds: UInt64 = 1_500_000_000

    private init() {
        session = BiliURLSessionFactory.makeImageSession()
        let initialBudget = RemoteImageAdaptiveBudget.current
        appliedBudget = initialBudget
        cache.countLimit = initialBudget.memoryEntryLimit
        cache.totalCostLimit = initialBudget.memoryCostLimit
        BiliURLSessionFactory.imageURLCache.memoryCapacity = initialBudget.urlCacheMemoryCapacity
        BiliURLSessionFactory.imageURLCache.diskCapacity = initialBudget.diskCapacity
    }

    func applyAdaptiveBudget() {
        applyAdaptiveBudgetIfNeeded()
    }

    func clearMemoryCache(cancelInFlight: Bool = false) {
        cache.removeAllObjects()
        evictions += storedKeys.count
        storedKeys.removeAll()
        guard cancelInFlight else { return }
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        inFlightOrder.removeAll()
        failedLoads.removeAll()
    }

    func refreshNetworkSessionForPathChange() {
        applyAdaptiveBudgetIfNeeded()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        inFlightOrder.removeAll()
        failedLoads.removeAll()
        let oldSession = session
        session = BiliURLSessionFactory.makeImageSession()
        oldSession.finishTasksAndInvalidate()
    }

    func image(for url: URL, scale: CGFloat = 1, targetPixelSize: Int? = nil) -> UIImage? {
        let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
        if let image = cache.object(forKey: key.nsKey) {
            hits += 1
            return image
        }
        misses += 1
        return nil
    }

    func clearDiskCache() {
        diskTrimTask?.cancel()
        diskTrimTask = nil
        BiliURLSessionFactory.imageURLCache.removeAllCachedResponses()
        diskRequests.removeAll()
    }

    func clearFailure(for url: URL, scale: CGFloat = 1, targetPixelSize: Int? = nil) {
        let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
        failedLoads[key] = nil
    }

    func statistics() -> RemoteImageCacheStatistics {
        applyAdaptiveBudgetIfNeeded()
        trimDiskCacheIfNeeded(budget: appliedBudget ?? RemoteImageAdaptiveBudget.current)
        return RemoteImageCacheStatistics(
            memoryEntryCount: storedKeys.count,
            inFlightCount: inFlight.count,
            memoryCostLimit: cache.totalCostLimit,
            diskUsage: BiliURLSessionFactory.imageURLCache.currentDiskUsage,
            diskCapacity: BiliURLSessionFactory.imageURLCache.diskCapacity,
            hits: hits,
            misses: misses,
            stores: stores,
            evictions: evictions
        )
    }

    func prefetch(
        _ urls: [URL],
        scale: CGFloat = 1,
        targetPixelSize: Int? = 760,
        maximumConcurrentLoads: Int = 3
    ) async {
        await prefetch(
            urls.map { RemoteImageSource(url: $0) },
            scale: scale,
            targetPixelSize: targetPixelSize,
            maximumConcurrentLoads: maximumConcurrentLoads
        )
    }

    func prefetch(
        _ sources: [RemoteImageSource],
        scale: CGFloat = 1,
        targetPixelSize: Int? = 760,
        maximumConcurrentLoads: Int = 3
    ) async {
        applyAdaptiveBudgetIfNeeded()
        let imageBudget = RemoteImagePrefetchBudget.current
        let uniqueSources = uniquedSources(sources)
        let budgetedSources = Array(uniqueSources.prefix(imageBudget.maximumURLs))
        let candidates = budgetedSources.filter { source in
            source.urls.contains { url in
                let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
                return cachedImage(for: url, scale: scale, targetPixelSize: targetPixelSize) == nil
                    && inFlight[key] == nil
                    && !isTemporarilyFailed(key)
            }
        }
        guard !candidates.isEmpty else { return }

        let concurrentLoads = min(max(maximumConcurrentLoads, 1), imageBudget.maximumConcurrentLoads)
        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()

            for _ in 0..<concurrentLoads {
                guard let source = iterator.next() else { break }
                group.addTask {
                    await self.prefetchOne(source, scale: scale, targetPixelSize: targetPixelSize)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let source = iterator.next() else { continue }
                group.addTask {
                    await self.prefetchOne(source, scale: scale, targetPixelSize: targetPixelSize)
                }
            }
        }
    }

    func load(
        url: URL,
        scale: CGFloat,
        targetPixelSize: Int? = nil,
        cachePolicy: RemoteImageCachePolicy = .standard
    ) async -> UIImage? {
        applyAdaptiveBudgetIfNeeded()
        let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
        if cachePolicy == .standard,
           let cached = cachedImage(for: url, scale: scale, targetPixelSize: targetPixelSize) {
            hits += 1
            return cached
        }
        guard !isTemporarilyFailed(key) else {
            misses += 1
            return nil
        }

        if cachePolicy == .standard, let task = inFlight[key] {
            touchDiskRequest(key)
            let image = await task.value
            finish(key: key, image: image)
            return image
        }

        let task = makeLoadTask(url: url, scale: scale, targetPixelSize: targetPixelSize, cachePolicy: cachePolicy)
        registerInFlightTask(key)
        inFlight[key] = task
        let image = await task.value
        finish(key: key, image: image)
        return image
    }

    private func finish(key: ImageCacheKey, image: UIImage?) {
        unregisterInFlightTask(key)
        if let image {
            failedLoads[key] = nil
            cache.setObject(image, forKey: key.nsKey, cost: image.memoryCost)
            storedKeys.insert(key)
            stores += 1
            scheduleDiskTrimIfNeeded()
            ResourceCacheAutoTrim.schedule()
        } else {
            diskRequests[key] = nil
            failedLoads[key] = Date()
        }
    }

    private func prefetchOne(_ source: RemoteImageSource, scale: CGFloat, targetPixelSize: Int?) async {
        guard !Task.isCancelled else { return }
        for url in source.urls {
            let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
            guard cachedImage(for: url, scale: scale, targetPixelSize: targetPixelSize) == nil else { return }
            guard !isTemporarilyFailed(key) else { continue }
            if let task = inFlight[key] {
                touchDiskRequest(key)
                let image = await task.value
                finish(key: key, image: image)
                if image != nil { return }
                continue
            }

            let task = makeLoadTask(url: url, scale: scale, targetPixelSize: targetPixelSize, cachePolicy: .standard)
            registerInFlightTask(key)
            inFlight[key] = task
            let image = await task.value
            finish(key: key, image: image)
            if image != nil { return }
        }
    }

    private func makeLoadTask(
        url: URL,
        scale: CGFloat,
        targetPixelSize: Int?,
        cachePolicy: RemoteImageCachePolicy
    ) -> Task<UIImage?, Never> {
        let session = session
        let effectiveTargetPixelSize = effectiveTargetPixelSize(targetPixelSize, scale: scale)
        let request = Self.imageRequest(url: url, cachePolicy: cachePolicy)
        if cachePolicy == .standard {
            recordDiskRequest(key: cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize), request: request)
        }
        return Task(priority: .utility) { () -> UIImage? in
            do {
                let (data, response) = try await BiliNetworkRetry.data(
                    session: session,
                    request: request,
                    policy: .image
                )
                if let response = response as? HTTPURLResponse,
                   !(200..<300).contains(response.statusCode) {
                    return nil
                }
                guard !Task.isCancelled,
                      let decoded = UIImage.downsampledImage(data: data, scale: scale, targetPixelSize: effectiveTargetPixelSize)
                else { return nil }
                guard !decoded.hasAlphaChannel else { return decoded }
                return decoded.preparingForDisplay() ?? decoded
            } catch {
                return nil
            }
        }
    }

    private static func imageRequest(url: URL, cachePolicy: RemoteImageCachePolicy) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy.requestCachePolicy
        BiliURLSessionFactory.imageHeaders().forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        return request
    }

    private func cacheKey(for url: URL, scale: CGFloat, targetPixelSize: Int?) -> ImageCacheKey {
        ImageCacheKey(
            identity: url.absoluteString.biliImageCacheIdentityURLString(),
            targetPixelSize: effectiveTargetPixelSize(targetPixelSize, scale: scale)
        )
    }

    private func cachedImage(
        for url: URL,
        scale: CGFloat,
        targetPixelSize: Int?
    ) -> UIImage? {
        let key = cacheKey(for: url, scale: scale, targetPixelSize: targetPixelSize)
        return cache.object(forKey: key.nsKey)
    }

    private func isTemporarilyFailed(_ key: ImageCacheKey) -> Bool {
        guard let failedAt = failedLoads[key] else { return false }
        if Date().timeIntervalSince(failedAt) < failedLoadTTL {
            return true
        }
        failedLoads[key] = nil
        return false
    }

    private func uniquedSources(_ sources: [RemoteImageSource]) -> [RemoteImageSource] {
        var seen = Set<String>()
        return sources.filter { source in
            let identity = source.urls.map(\.absoluteString).joined(separator: "|")
            return !identity.isEmpty && seen.insert(identity).inserted
        }
    }

    private func applyAdaptiveBudgetIfNeeded() {
        let budget = RemoteImageAdaptiveBudget.current
        guard appliedBudget != budget else { return }
        appliedBudget = budget
        cache.countLimit = budget.memoryEntryLimit
        cache.totalCostLimit = budget.memoryCostLimit
        BiliURLSessionFactory.imageURLCache.memoryCapacity = budget.urlCacheMemoryCapacity
        BiliURLSessionFactory.imageURLCache.diskCapacity = budget.diskCapacity
        if budget.trimsMemoryImmediately {
            clearMemoryCache(cancelInFlight: false)
        }
        trimDiskCacheIfNeeded(budget: budget)
    }

    private func scheduleDiskTrimIfNeeded() {
        guard diskTrimTask == nil else { return }
        diskTrimTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.diskTrimDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self.performScheduledDiskTrim()
        }
    }

    private func performScheduledDiskTrim() {
        diskTrimTask = nil
        applyAdaptiveBudgetIfNeeded()
        trimDiskCacheIfNeeded(budget: appliedBudget ?? RemoteImageAdaptiveBudget.current)
    }

    private func trimDiskCacheIfNeeded(budget: RemoteImageAdaptiveBudget) {
        guard budget.trimsDiskWhenOverBudget,
              BiliURLSessionFactory.imageURLCache.currentDiskUsage > budget.diskCapacity + budget.diskTrimSlackBytes
        else { return }
        let targetUsage = max(0, budget.diskCapacity - budget.diskTrimSlackBytes / 2)
        for key in diskRequests
            .sorted(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })
            .map(\.key) {
            guard BiliURLSessionFactory.imageURLCache.currentDiskUsage > targetUsage else { return }
            guard let entry = diskRequests.removeValue(forKey: key) else { continue }
            BiliURLSessionFactory.imageURLCache.removeCachedResponse(for: entry.request)
            evictions += 1
        }
        guard BiliURLSessionFactory.imageURLCache.currentDiskUsage > budget.diskCapacity + budget.diskTrimSlackBytes else { return }
        BiliURLSessionFactory.imageURLCache.removeAllCachedResponses()
        evictions += diskRequests.count
        diskRequests.removeAll()
    }

    private func recordDiskRequest(key: ImageCacheKey, request: URLRequest) {
        diskRequests[key] = DiskRequestEntry(request: request, lastAccessedAt: Date())
    }

    private func touchDiskRequest(_ key: ImageCacheKey) {
        guard var entry = diskRequests[key] else { return }
        entry.lastAccessedAt = Date()
        diskRequests[key] = entry
    }

    private func effectiveTargetPixelSize(_ targetPixelSize: Int?, scale: CGFloat) -> Int {
        let requested = targetPixelSize ?? Int((1200 * max(scale, 1)).rounded(.up))
        let environment = PlaybackEnvironment.current
        let defaultMaximumPixelSize: Int
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            defaultMaximumPixelSize = 640
        } else {
            switch environment.networkClass {
            case .wifi, .unknown:
                defaultMaximumPixelSize = 1280
            case .cellular, .constrained:
                defaultMaximumPixelSize = 760
            }
        }
        let maximumPixelSize: Int
        if targetPixelSize == nil {
            maximumPixelSize = defaultMaximumPixelSize
        } else if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            maximumPixelSize = 960
        } else {
            switch environment.networkClass {
            case .wifi, .unknown:
                maximumPixelSize = 2600
            case .cellular, .constrained:
                maximumPixelSize = 1024
            }
        }
        return max(96, min(requested, maximumPixelSize))
    }

    private func registerInFlightTask(_ key: ImageCacheKey) {
        inFlightOrder.removeAll { $0 == key }
        inFlightOrder.append(key)
        while inFlightOrder.count > maximumInFlightLoads {
            let evicted = inFlightOrder.removeFirst()
            guard evicted != key else { continue }
            inFlight[evicted]?.cancel()
            inFlight[evicted] = nil
        }
    }

    private func unregisterInFlightTask(_ key: ImageCacheKey) {
        inFlight[key] = nil
        inFlightOrder.removeAll { $0 == key }
    }
}

nonisolated private struct RemoteImagePrefetchBudget: Sendable {
    let maximumURLs: Int
    let maximumConcurrentLoads: Int

    nonisolated static var current: RemoteImagePrefetchBudget {
        let environment = PlaybackEnvironment.current
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            return RemoteImagePrefetchBudget(maximumURLs: 3, maximumConcurrentLoads: 1)
        }
        switch environment.networkClass {
        case .wifi, .unknown:
            return RemoteImagePrefetchBudget(maximumURLs: 8, maximumConcurrentLoads: 2)
        case .cellular, .constrained:
            return RemoteImagePrefetchBudget(maximumURLs: 4, maximumConcurrentLoads: 1)
        }
    }
}

nonisolated private struct RemoteImageAdaptiveBudget: Equatable, Sendable {
    let memoryEntryLimit: Int
    let memoryCostLimit: Int
    let urlCacheMemoryCapacity: Int
    let diskCapacity: Int
    let diskTrimSlackBytes: Int
    let trimsMemoryImmediately: Bool
    let trimsDiskWhenOverBudget: Bool

    nonisolated static var current: RemoteImageAdaptiveBudget {
        let environment = PlaybackEnvironment.current
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            return RemoteImageAdaptiveBudget(
                memoryEntryLimit: 160,
                memoryCostLimit: 28 * 1024 * 1024,
                urlCacheMemoryCapacity: 12 * 1024 * 1024,
                diskCapacity: 192 * 1024 * 1024,
                diskTrimSlackBytes: 24 * 1024 * 1024,
                trimsMemoryImmediately: true,
                trimsDiskWhenOverBudget: true
            )
        }
        switch environment.networkClass {
        case .wifi, .unknown:
            return RemoteImageAdaptiveBudget(
                memoryEntryLimit: 420,
                memoryCostLimit: 72 * 1024 * 1024,
                urlCacheMemoryCapacity: 32 * 1024 * 1024,
                diskCapacity: 512 * 1024 * 1024,
                diskTrimSlackBytes: 64 * 1024 * 1024,
                trimsMemoryImmediately: false,
                trimsDiskWhenOverBudget: true
            )
        case .cellular, .constrained:
            return RemoteImageAdaptiveBudget(
                memoryEntryLimit: 240,
                memoryCostLimit: 40 * 1024 * 1024,
                urlCacheMemoryCapacity: 18 * 1024 * 1024,
                diskCapacity: 256 * 1024 * 1024,
                diskTrimSlackBytes: 32 * 1024 * 1024,
                trimsMemoryImmediately: false,
                trimsDiskWhenOverBudget: true
            )
        }
    }
}

nonisolated private struct ImageCacheKey: Hashable, Sendable {
    let identity: String
    let targetPixelSize: Int?

    nonisolated var nsKey: NSURL {
        let cacheString = "\(identity)#px=\(targetPixelSize ?? 0)"
        return NSURL(string: cacheString) ?? NSURL(fileURLWithPath: cacheString)
    }
}

private struct DiskRequestEntry {
    let request: URLRequest
    var lastAccessedAt: Date
}

private extension UIImage {
    nonisolated static func downsampledImage(data: Data, scale: CGFloat, targetPixelSize: Int?) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data, scale: scale)
        }

        let maxPixelSize = max(96, targetPixelSize ?? Int(1200 * max(scale, 1)))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return UIImage(data: data, scale: scale)
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    nonisolated var memoryCost: Int {
        guard let cgImage else { return 1 }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }

    nonisolated var hasAlphaChannel: Bool {
        guard let cgImage else { return false }
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}

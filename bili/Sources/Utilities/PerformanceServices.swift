import AVFoundation
import Combine
import ImageIO
import OSLog
import SwiftUI
import UIKit

actor VideoPreloadCenter {
    static let shared = VideoPreloadCenter()

    private let maxConcurrentPreloads = 3
    private let cachedPlayURLTTL: TimeInterval = 12 * 60
    private let stalePlayablePlayURLTTL: TimeInterval = 20 * 60
    private let maxCachedPlayURLCount = 32
    private let cachedDetailTTL: TimeInterval = 180
    private let maxCachedDetailCount = 24
    private let mediaWarmupTTL: TimeInterval = 120
    private let maxMediaWarmupCount = 32
    private var defaultPreferredQuality: Int?
    private var tasks: [String: Task<PlayURLData?, Never>] = [:]
    private var taskUserInitiatedFlags: [String: Bool] = [:]
    private var taskPreferredQualities: [String: Int?] = [:]
    private var detailTasks: [String: Task<VideoItem, Error>] = [:]
    private var detailTaskUserInitiatedFlags: [String: Bool] = [:]
    private var bvidPlayInfoTasks: [String: Task<PlayURLData?, Never>] = [:]
    private var bvidPlayInfoTaskPreferredQualities: [String: Int?] = [:]
    private var bvidPlayInfoCache: [String: CachedPlayURL] = [:]
    private var mediaWarmupTasks: [String: Task<Void, Never>] = [:]
    private var activeOrder: [String] = []
    private var playURLCache: [String: CachedPlayURL] = [:]
    private var detailCache: [String: CachedVideoDetail] = [:]
    private var mediaWarmupCache: [String: Date] = [:]
    private var focusedPlaybackBVID: String?
    private var focusedPlaybackUntil: Date?

    func updatePlaybackPreferences(preferredQuality: Int?) {
        defaultPreferredQuality = preferredQuality
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
        mediaWarmupDelay: TimeInterval = 1.25,
        priority: TaskPriority = .utility
    ) {
        guard shouldAllowPreload(bvid: video.bvid, priority: priority) else { return }
        guard let cid = video.cid else {
            preloadDetailAndPlayback(
                video,
                api: api,
                warmsMedia: warmsMedia,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority
            )
            return
        }
        preloadPlayURL(
            bvid: video.bvid,
            cid: cid,
            page: nil,
            api: api,
            warmsMedia: warmsMedia,
            mediaWarmupDelay: mediaWarmupDelay,
            priority: priority
        )
    }

    func preloadPlayInfo(
        _ video: VideoItem,
        api: BiliAPIClient,
        preferredQuality: Int?,
        priority: TaskPriority = .utility,
        warmsMedia: Bool = false,
        mediaWarmupDelay: TimeInterval = 0
    ) {
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback || priority == .userInitiated else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadSkipped reason=conservative bvid=\(video.bvid, privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public)"
            )
            return
        }
        defaultPreferredQuality = preferredQuality
        guard let cid = video.cid else {
            PlayerMetricsLog.logger.info(
                "playInfoPreloadDetailStart bvid=\(video.bvid, privacy: .public) preferred=\(preferredQuality ?? 0, privacy: .public) priority=\(String(describing: priority), privacy: .public)"
            )
            preloadWebPagePlayInfo(
                bvid: video.bvid,
                api: api,
                preferredQuality: preferredQuality,
                priority: priority
            )
            preloadDetailAndPlayback(
                video,
                api: api,
                preferredQuality: preferredQuality,
                warmsMedia: warmsMedia,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority
            )
            return
        }
        preloadPlayURL(
            bvid: video.bvid,
            cid: cid,
            page: nil,
            preferredQuality: preferredQuality,
            api: api,
            warmsMedia: warmsMedia,
            mediaWarmupDelay: mediaWarmupDelay,
            priority: priority
        )
    }

    private func preloadPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int? = nil,
        api: BiliAPIClient,
        warmsMedia: Bool,
        mediaWarmupDelay: TimeInterval,
        priority: TaskPriority
    ) {
        let effectivePreferredQuality = preferredQuality ?? defaultPreferredQuality
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
                    warmsMedia: true,
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
                    preferredQuality: effectivePreferredQuality
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
                    warmsMedia: warmsMedia,
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
        warmsMedia: Bool = true,
        mediaWarmupDelay: TimeInterval = 1.25,
        priority: TaskPriority = .utility
    ) {
        guard shouldAllowPreload(bvid: video.bvid, priority: priority) else { return }
        if let cid = video.cid {
            preloadPlayURL(
                bvid: video.bvid,
                cid: cid,
                page: nil,
                preferredQuality: preferredQuality,
                api: api,
                warmsMedia: warmsMedia,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority
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
                preferredQuality: preferredQuality,
                api: api,
                warmsMedia: warmsMedia,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority
            )
            return
        }
        preloadWebPagePlayInfo(
            bvid: video.bvid,
            api: api,
            preferredQuality: preferredQuality,
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
                preferredQuality: preferredQuality,
                warmsMedia: warmsMedia,
                mediaWarmupDelay: mediaWarmupDelay,
                priority: priority
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
                        preferredQuality: preferredQuality,
                        warmsMedia: warmsMedia,
                        mediaWarmupDelay: mediaWarmupDelay
                    ) {
                        self.finishDetail(bvid)
                        return detail
                    }
                    self.preloadPlayURL(
                        bvid: detail.bvid,
                        cid: cid,
                        page: nil,
                        preferredQuality: preferredQuality,
                        api: api,
                        warmsMedia: warmsMedia,
                        mediaWarmupDelay: mediaWarmupDelay,
                        priority: priority
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
        warmsMedia: Bool,
        mediaWarmupDelay: TimeInterval,
        priority: TaskPriority
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
                    warmsMedia: warmsMedia,
                    mediaWarmupDelay: mediaWarmupDelay
                ) {
                    return
                }
                self.preloadPlayURL(
                    bvid: detail.bvid,
                    cid: cid,
                    page: nil,
                    preferredQuality: preferredQuality,
                    api: api,
                    warmsMedia: warmsMedia,
                    mediaWarmupDelay: mediaWarmupDelay,
                    priority: priority
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
                self.bvidPlayInfoCache[key] = CachedPlayURL(data: data, date: Date())
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
        warmsMedia: Bool,
        mediaWarmupDelay: TimeInterval
    ) async -> Bool {
        let effectivePreferredQuality = preferredQuality ?? defaultPreferredQuality
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
                    warmsMedia: warmsMedia,
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
                        warmsMedia: warmsMedia,
                        mediaWarmupDelay: mediaWarmupDelay,
                        source: "pending"
                    )
                }
            }
        }
        return false
    }

    private func storeBVIDPlayInfoDataIfNeeded(
        _ data: PlayURLData,
        bvid: String,
        cid: Int,
        page: Int?,
        preferredQuality: Int?,
        warmsMedia: Bool,
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
                    warmsMedia: true,
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
            warmsMedia: warmsMedia,
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
                    warmsMedia: false,
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
        warmsMedia: Bool = true,
        mediaWarmupDelay: TimeInterval = 0
    ) {
        guard data.hasPlayableStreamPayload else { return }
        let effectivePage = normalizedPage(page)
        playURLCache[cacheKey(bvid: bvid, cid: cid, page: effectivePage)] = CachedPlayURL(
            data: data,
            date: Date()
        )
        if let preferredQuality {
            playURLCache[cacheKey(
                bvid: bvid,
                cid: cid,
                page: effectivePage,
                preferredQuality: preferredQuality
            )] = CachedPlayURL(
                data: data,
                date: Date()
            )
        }
        if warmsMedia {
            scheduleMediaWarmup(
                data,
                bvid: bvid,
                cid: cid,
                preferredQuality: preferredQuality,
                page: effectivePage,
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

        cancelMediaWarmups(except: video)
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
        var keys = [
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
        delay: TimeInterval = 0
    ) {
        let key = cacheKey(bvid: bvid, cid: cid, page: page)
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
                preferredQuality: preferredQuality
            )
            self.finishMediaWarmup(key, didWarm: didWarm)
        }
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
        let expiry = Date().addingTimeInterval(-ttl)
        playURLCache = playURLCache.filter { $0.value.date >= expiry }
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
        let expiry = Date().addingTimeInterval(-cachedPlayURLTTL)
        bvidPlayInfoCache = bvidPlayInfoCache.filter { $0.value.date >= expiry }
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

    private nonisolated static func warmAsset(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        _ = try? await asset.load(.duration)
        return playable
    }

    private nonisolated static func warmPlayableMedia(
        _ data: PlayURLData,
        bvid: String,
        preferredQuality: Int?
    ) async -> Bool {
        let media: (
            videoURL: URL,
            audioURL: URL?,
            videoTrack: DASHStream?,
            audioTrack: DASHStream?,
            dynamicRange: BiliVideoDynamicRange
        )? = await MainActor.run {
            guard let variant = preferredPlayableVariant(
                in: data.playVariants,
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
            bvid: bvid
        )
    }

    private nonisolated static func warmPlayableMedia(_ source: PlayableMediaWarmupSource, bvid: String) async -> Bool {
        let videoURL = source.videoURL
        if let videoTrack = source.videoTrack {
            let audioTrack = source.audioTrack.flatMap { track -> HLSBridgeTrack? in
                guard let audioURL = source.audioURL else { return nil }
                return HLSBridgeTrack(
                    url: audioURL,
                    fallbackURLs: track.backupPlayURLs,
                    stream: track,
                    mediaType: .audio
                )
            }
            return await LocalHLSBridge.warmup(
                videoTrack: HLSBridgeTrack(
                    url: videoURL,
                    fallbackURLs: videoTrack.backupPlayURLs,
                    stream: videoTrack,
                    mediaType: .video,
                    dynamicRange: source.dynamicRange
                ),
                audioTrack: audioTrack,
                headers: Self.httpHeaders(referer: "https://www.bilibili.com/video/\(bvid)")
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

    private nonisolated static func preferredPlayableVariant(
        in variants: [PlayVariant],
        preferredQuality: Int?
    ) -> PlayVariant? {
        let playableVariants = variants
            .filter(\.isPlayable)
            .sorted { lhs, rhs in
                if lhs.isProgressiveFastStart != rhs.isProgressiveFastStart {
                    return !lhs.isProgressiveFastStart && rhs.isProgressiveFastStart
                }
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
            }

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

actor VideoRangeCache {
    static let shared = VideoRangeCache()

    private let maxCacheBytes: Int64 = 512 * 1024 * 1024
    private let fileManager = FileManager.default
    private let rootURL: URL
    private var pendingFetches: [String: Task<Data, Error>] = [:]
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
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    func cachedOrFetch(
        url: URL,
        range: HTTPByteRange,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let cached = data(url: url, range: range) {
            return cached
        }

        let key = cacheKey(url: url, range: range)
        if let pendingFetch = pendingFetches[key] {
            return try await pendingFetch.value
        }

        let pendingFetch = Task.detached(priority: .userInitiated) {
            try await loader()
        }
        pendingFetches[key] = pendingFetch

        do {
            let data = try await pendingFetch.value
            pendingFetches[key] = nil
            store(data, url: url, range: range)
            return data
        } catch {
            pendingFetches[key] = nil
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
        guard range.length <= maxCacheBytes else {
            return .unreserved
        }

        let completion = VideoRangePendingCompletion()
        let pendingFetch = Task.detached(priority: .userInitiated) {
            try await completion.value()
        }
        pendingFetches[key] = pendingFetch
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
        token.completion.succeed(data)
        store(data, url: token.url, range: token.range)
    }

    func failExternalFetch(_ token: VideoRangeExternalFetchToken, error: Error) {
        guard pendingFetches[token.key] != nil else { return }
        pendingFetches[token.key] = nil
        token.completion.fail(error)
    }

    func store(_ data: Data, url: URL, range: HTTPByteRange) {
        guard !data.isEmpty else { return }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL(url: url, range: range), options: .atomic)
            estimatedCacheBytes = (estimatedCacheBytes ?? 0) + Int64(data.count)
            scheduleTrimIfNeeded()
        } catch {}
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
        guard totalSize > maxCacheBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxCacheBytes { break }
        }
        estimatedCacheBytes = totalSize
    }
}

enum VideoRangeExternalFetchReservation: Sendable {
    case cached(Data)
    case pending(Task<Data, Error>)
    case reserved(VideoRangeExternalFetchToken)
    case unreserved
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

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let scale: CGFloat
    let targetPixelSize: Int?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = CachedRemoteImageLoader()

    init(
        url: URL?,
        scale: CGFloat = 1,
        targetPixelSize: Int? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.targetPixelSize = targetPixelSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) {
            await loader.load(url: url, scale: scale, targetPixelSize: targetPixelSize)
        }
        .onDisappear {
            loader.cancel()
            if loader.image == nil {
                loader.reset()
            }
        }
    }

    private var cacheIdentity: String {
        "\(url?.absoluteString ?? "")|\(targetPixelSize ?? 0)"
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?

    func load(url: URL?, scale: CGFloat, targetPixelSize: Int?) async {
        task?.cancel()
        guard let url else {
            image = nil
            return
        }
        image = nil

        if let cachedImage = await RemoteImageCache.shared.image(for: url, targetPixelSize: targetPixelSize) {
            image = cachedImage
            return
        }

        task = Task(priority: .utility) { [weak self] in
            guard let loadedImage = await RemoteImageCache.shared.load(url: url, scale: scale, targetPixelSize: targetPixelSize),
                  !Task.isCancelled
            else { return }
            await MainActor.run {
                self?.image = loadedImage
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
        image = nil
    }
}

actor RemoteImageCache {
    static let shared = RemoteImageCache()
    private static let imageUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    private static let diskCache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: 512 * 1024 * 1024,
        directory: URL.cachesDirectory.appending(path: "BiliRemoteImageCache", directoryHint: .isDirectory)
    )

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [ImageCacheKey: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = Self.diskCache
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 24
        configuration.httpAdditionalHeaders = [
            "Referer": "https://www.bilibili.com/",
            "User-Agent": Self.imageUserAgent,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"
        ]
        session = URLSession(configuration: configuration)
        cache.countLimit = 520
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func clearMemoryCache(cancelInFlight: Bool = false) {
        cache.removeAllObjects()
        guard cancelInFlight else { return }
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    func image(for url: URL, targetPixelSize: Int? = nil) -> UIImage? {
        cache.object(forKey: cacheKey(for: url, targetPixelSize: targetPixelSize).nsKey)
    }

    func prefetch(
        _ urls: [URL],
        scale: CGFloat = 1,
        targetPixelSize: Int? = 760,
        maximumConcurrentLoads: Int = 3
    ) async {
        let uniqueURLs = urls.reduce(into: [URL]()) { partialResult, url in
            guard !partialResult.contains(url) else { return }
            partialResult.append(url)
        }
        let candidates = uniqueURLs.filter { url in
            let key = cacheKey(for: url, targetPixelSize: targetPixelSize)
            return image(for: url, targetPixelSize: targetPixelSize) == nil && inFlight[key] == nil
        }
        guard !candidates.isEmpty else { return }

        let concurrentLoads = min(max(maximumConcurrentLoads, 1), 4)
        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()

            for _ in 0..<concurrentLoads {
                guard let url = iterator.next() else { break }
                group.addTask {
                    await self.prefetchOne(url, scale: scale, targetPixelSize: targetPixelSize)
                }
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                guard let url = iterator.next() else { continue }
                group.addTask {
                    await self.prefetchOne(url, scale: scale, targetPixelSize: targetPixelSize)
                }
            }
        }
    }

    func load(url: URL, scale: CGFloat, targetPixelSize: Int? = nil) async -> UIImage? {
        let key = cacheKey(for: url, targetPixelSize: targetPixelSize)
        if let cached = image(for: url, targetPixelSize: targetPixelSize) {
            return cached
        }

        if let task = inFlight[key] {
            let image = await task.value
            finish(key: key, image: image)
            return image
        }

        let task = makeLoadTask(url: url, scale: scale, targetPixelSize: targetPixelSize)
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            cache.setObject(image, forKey: key.nsKey, cost: image.memoryCost)
        }
        return image
    }

    private func finish(key: ImageCacheKey, image: UIImage?) {
        inFlight[key] = nil
        if let image {
            cache.setObject(image, forKey: key.nsKey, cost: image.memoryCost)
        }
    }

    private func prefetchOne(_ url: URL, scale: CGFloat, targetPixelSize: Int?) async {
        guard !Task.isCancelled else { return }
        let key = cacheKey(for: url, targetPixelSize: targetPixelSize)
        guard image(for: url, targetPixelSize: targetPixelSize) == nil else { return }
        if let task = inFlight[key] {
            let image = await task.value
            finish(key: key, image: image)
            return
        }

        let task = makeLoadTask(url: url, scale: scale, targetPixelSize: targetPixelSize)
        inFlight[key] = task
        let image = await task.value
        finish(key: key, image: image)
    }

    private func makeLoadTask(url: URL, scale: CGFloat, targetPixelSize: Int?) -> Task<UIImage?, Never> {
        let session = session
        return Task(priority: .utility) { () -> UIImage? in
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
                request.setValue(Self.imageUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                let (data, _) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let decoded = UIImage.downsampledImage(data: data, scale: scale, targetPixelSize: targetPixelSize)
                else { return nil }
                return decoded.preparingForDisplay() ?? decoded
            } catch {
                return nil
            }
        }
    }

    private func cacheKey(for url: URL, targetPixelSize: Int?) -> ImageCacheKey {
        ImageCacheKey(url: url, targetPixelSize: targetPixelSize)
    }
}

private struct ImageCacheKey: Hashable {
    let url: URL
    let targetPixelSize: Int?

    nonisolated var nsKey: NSURL {
        let cacheString = "\(url.absoluteString)#px=\(targetPixelSize ?? 0)"
        return NSURL(string: cacheString) ?? (url as NSURL)
    }
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
}

import Foundation
import QuartzCore

extension VideoDetailViewModel {
    private static var coldStartPackageWarmupPlayerCreationWait: TimeInterval { 0.08 }
    private static var cachedPlayURLStartupPackageWarmupPlayerCreationWait: TimeInterval { 0.16 }
    private static var historyResumeWarmupPlayerCreationWait: TimeInterval {
        let normalBudget = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 0.18 : 0.12
        return ResourceLoadingExperiment.resumeWarmupWait(normalBudget: normalBudget)
    }

    func schedulePostPlayURLApplicationWork(
        selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let resumeTime = consumePendingPlaybackHistoryResumeTime(for: cid)
        await scheduleSelectedStartupPackageWarmupBeforeFirstFrame(
            selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        scheduleSelectedStartupPackageWarmupAfterFirstFrame(selectedVariant, cid: cid, page: page)
        await waitForStartupPackageWarmupBeforePlayerCreationIfNeeded(
            selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        scheduleHistoryResumeWarmupInBackgroundIfNeeded(
            selectedVariant,
            cid: cid,
            page: page,
            resumeTime: resumeTime
        )
        updateStablePlayerViewModelIfNeeded(resumeTimeOverride: resumeTime)
        playURLState = .loaded
        warmSelectedVariantAfterFirstFrameIfNeeded(selectedVariant, cid: cid, page: page)
        scheduleAutomaticCDNRecommendationAfterFirstFrameIfNeeded(
            variant: selectedVariant,
            cid: cid,
            page: page
        )
        rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(selectedVariant, cid: cid)
        scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
            startupVariant: selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
    }

    /// 恢复位置预热不再阻塞播放器创建：后台预热目标位置数据，完成后仅记录观测。
    /// 首帧本来就要等恢复位置的数据，预热与播放器取流经 VideoRangeCache 去重共享，
    /// 旧实现等满 220ms 预算只对极少数缓存命中有益，却让带进度的打开普遍多付 220ms。
    private func scheduleHistoryResumeWarmupInBackgroundIfNeeded(
        _ selectedVariant: PlayVariant?,
        cid: Int?,
        page: Int?,
        resumeTime: TimeInterval?
    ) {
        guard stablePlayerViewModel == nil,
            !isPlaybackInvalidatedForNavigation,
            let cid,
            let selectedVariant,
            selectedVariant.isPlayable,
            !selectedVariant.isProgressiveFastStart,
            let resumeTime,
            resumeTime > 0.25
        else { return }

        let bvid = detail.bvid
        let selectedVariantID = selectedVariant.id
        let startedAt = CACurrentMediaTime()
        let budget = Self.historyResumeWarmupPlayerCreationWait
        Task { @MainActor [weak self, selectedVariant] in
            let didWarm = await VideoPreloadCenter.shared.warmVariantAroundSeek(
                selectedVariant,
                bvid: bvid,
                cid: cid,
                page: page,
                playbackTime: resumeTime,
                timeout: budget
            )
            guard let self,
                !self.isPlaybackInvalidatedForNavigation,
                self.detail.bvid == bvid,
                self.selectedCID == cid,
                self.selectedPlayVariant?.id == selectedVariantID
            else { return }
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
            PlayerMetricsLog.record(
                .manifestStage,
                metricsID: bvid,
                title: self.detail.title,
                message: [
                    "historyResumeWarm=\(didWarm ? "hit" : "timeout")",
                    "mode=background",
                    "target=\(String(format: "%.2fs", resumeTime))",
                    "\(Int(elapsedMilliseconds.rounded()))ms",
                    "budget=\(Int((budget * 1000).rounded()))ms",
                    "q\(selectedVariant.quality)",
                ].joined(separator: " ")
            )
            guard ResourceLoadingExperiment.isFeatureEnabled(.resumePacketWarmup) else { return }
            ResourceLoadingDiagnostics.shared.record(
                didWarm ? .resumeWarmupHit : .resumeWarmupTimeout,
                durationMilliseconds: Int(elapsedMilliseconds.rounded()),
                details: [
                    "budget": "\(Int((budget * 1000).rounded()))ms",
                    "quality": "q\(selectedVariant.quality)",
                ]
            )
        }
    }

    private func waitForStartupPackageWarmupBeforePlayerCreationIfNeeded(
        _ selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard stablePlayerViewModel == nil,
            !isPlaybackInvalidatedForNavigation,
            let cid,
            let selectedVariant,
            selectedVariant.isPlayable
        else { return }

        let bvid = detail.bvid
        let selectedVariantID = selectedVariant.id
        let startedAt = CACurrentMediaTime()
        let timeout = startupPackageWarmupPlayerCreationWaitForCurrentLoad()
        let result = await VideoPreloadCenter.shared.prebuildStartupPackageAndWait(
            variant: selectedVariant,
            targetVariant: targetVariant,
            bvid: bvid,
            cid: cid,
            page: page,
            durationHint: detail.duration.map(TimeInterval.init),
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            timeout: timeout
        )
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
        guard !isPlaybackInvalidatedForNavigation,
            detail.bvid == bvid,
            selectedCID == cid,
            selectedPlayVariant?.id == selectedVariantID
        else { return }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: bvid,
            message: [
                "startupWarmWait=\(result.rawValue)",
                "mode=immediateCreate",
                "\(Int(elapsedMilliseconds.rounded()))ms",
                "budget=\(Int((timeout * 1000).rounded()))ms",
                "codec=\(selectedVariant.codec?.replacingOccurrences(of: " ", with: "_") ?? "-")",
            ].joined(separator: " ")
        )
    }

    private func startupPackageWarmupPlayerCreationWaitForCurrentLoad() -> TimeInterval {
        let normalBudget: TimeInterval
        if lastPlayURLSource?.localizedCaseInsensitiveContains("cache") == true {
            normalBudget = Self.cachedPlayURLStartupPackageWarmupPlayerCreationWait
        } else {
            normalBudget = Self.coldStartPackageWarmupPlayerCreationWait
        }
        return AVPlayerStartupPathOptimizationExperiment.playerCreationWarmupWait(
            normalBudget: normalBudget
        )
    }
}

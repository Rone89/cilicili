import Foundation
import QuartzCore

extension VideoDetailViewModel {
    private static var startupPackageWarmupPlayerCreationWait: TimeInterval { 0.14 }
    private static var slowPlayURLStartupPackageWarmupPlayerCreationWait: TimeInterval { 0.32 }
    private static var av1StartupPackageWarmupPlayerCreationWait: TimeInterval { 0.84 }
    private static var av1ConservativeStartupPackageWarmupPlayerCreationWait: TimeInterval { 0.34 }
    private static var av1SlowPlayURLStartupPackageWarmupPlayerCreationWait: TimeInterval { 0.84 }
    private static var slowPlayURLWarmupThresholdMilliseconds: Int { 350 }

    func schedulePostPlayURLApplicationWork(
        variants: [PlayVariant],
        selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?,
        schedulesSupplementalLoad: Bool
    ) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        cancelFastStartUpgradeTask()
        await prebuildAV1StartupPackageBeforePlayerCreationIfNeeded(
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
        updateStablePlayerViewModelIfNeeded()
        playURLState = .loaded
        warmSelectedVariantAfterFirstFrameIfNeeded(selectedVariant, cid: cid, page: page)
        scheduleAutomaticCDNRecommendationAfterFirstFrameIfNeeded(cid: cid, page: page)
        rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(selectedVariant, cid: cid)
        scheduleHLSRenditionPrebuildAfterFirstFrameIfNeeded(
            startupVariant: selectedVariant,
            targetVariant: targetVariant,
            cid: cid,
            page: page
        )
        clearSupplementalPlayURLState()
        if schedulesSupplementalLoad {
            scheduleSupplementalTargetQualityLoadIfNeeded(
                variants: variants,
                cid: cid,
                page: page
            )
        }
    }

    private func prebuildAV1StartupPackageBeforePlayerCreationIfNeeded(
        _ selectedVariant: PlayVariant?,
        targetVariant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) async {
        guard stablePlayerViewModel == nil,
              !isPlaybackInvalidatedForNavigation,
              libraryStore.isPlaybackAutoOptimizationEnabled,
              let cid,
              let selectedVariant,
              selectedVariant.isPlayable,
              Self.isAV1StartupVariant(selectedVariant)
        else { return }

        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return }
        switch environment.networkClass {
        case .wifi, .unknown:
            break
        case .cellular, .constrained:
            return
        }

        let bvid = detail.bvid
        let selectedVariantID = selectedVariant.id
        let result = await VideoPreloadCenter.shared.prebuildStartupPackageAndWait(
            variant: selectedVariant,
            targetVariant: targetVariant,
            bvid: bvid,
            cid: cid,
            page: page,
            durationHint: detail.duration.map(TimeInterval.init),
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            timeout: 0
        )
        guard !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid,
              selectedCID == cid,
              selectedPlayVariant?.id == selectedVariantID
        else { return }

        let state: String
        switch result {
        case .ready:
            state = "ready"
        case .timeout:
            state = "queued"
        case .missing:
            state = "missing"
        }
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: bvid,
            message: [
                "av1EarlyWarmup=\(state)",
                "variant=q\(selectedVariant.quality)",
                "network=\(environment.networkClass.performanceSampleKey)"
            ].joined(separator: " ")
        )
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
        let timeout = startupPackageWarmupPlayerCreationWaitForCurrentLoad(selectedVariant)
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
                "\(Int(elapsedMilliseconds.rounded()))ms",
                "budget=\(Int((timeout * 1000).rounded()))ms",
                "codec=\(Self.startupWarmupCodecLabel(for: selectedVariant))"
            ].joined(separator: " ")
        )
    }

    private func startupPackageWarmupPlayerCreationWaitForCurrentLoad(_ variant: PlayVariant) -> TimeInterval {
        let isSlowPlayURL = (playURLElapsedMilliseconds ?? 0) >= Self.slowPlayURLWarmupThresholdMilliseconds
        var wait = isSlowPlayURL
            ? Self.slowPlayURLStartupPackageWarmupPlayerCreationWait
            : Self.startupPackageWarmupPlayerCreationWait

        guard Self.isAV1StartupVariant(variant) else {
            return wait
        }

        let av1Wait = PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? Self.av1ConservativeStartupPackageWarmupPlayerCreationWait
            : Self.av1StartupPackageWarmupPlayerCreationWait
        wait = max(wait, av1Wait)
        if isSlowPlayURL {
            wait = max(wait, Self.av1SlowPlayURLStartupPackageWarmupPlayerCreationWait)
        }
        return wait
    }

    private nonisolated static func isAV1StartupVariant(_ variant: PlayVariant) -> Bool {
        if variant.videoStream?.isAV1VideoCodec == true {
            return true
        }
        let codec = (variant.codec ?? "").lowercased()
        return codec.contains("av1") || codec.contains("av01")
    }

    private nonisolated static func startupWarmupCodecLabel(for variant: PlayVariant) -> String {
        if isAV1StartupVariant(variant) {
            return "AV1"
        }
        return variant.codec?.replacingOccurrences(of: " ", with: "_") ?? "-"
    }
}

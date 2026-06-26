import Foundation
import OSLog

extension VideoDetailViewModel {
    func recordStartupPlaybackMetrics(
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate,
        playerViewModel: PlayerStateViewModel,
        firstFrameElapsedMilliseconds: Int
    ) {
        let detailElapsed = elapsedMilliseconds(since: detailLoadStartTime)
        let playURLElapsed = playURLElapsedMilliseconds ?? elapsedMilliseconds(since: playURLLoadStartTime)
        let prepareElapsed = playerViewModel.prepareElapsedMilliseconds
        let playbackElapsed = playerViewModel.firstFrameElapsedMilliseconds ?? firstFrameElapsedMilliseconds
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let environment = PlaybackEnvironment.current
        let resumeText = resumeCandidate.time > 0.25
            ? String(format: "%.2fs", resumeCandidate.time)
            : "none"
        let summary = [
            "detail=\(formattedMilliseconds(detailElapsed))",
            "playurl=\(formattedMilliseconds(playURLElapsed))",
            "prepare=\(formattedMilliseconds(prepareElapsed))",
            "firstFrame=\(formatMilliseconds(playbackElapsed))",
            "resume=\(resumeText)",
            "cid=\(selectedCID ?? 0)",
            "source=\(lastPlayURLSource ?? "-")",
            "q=\(variant.quality)",
            "targetQ=\(targetPlaybackPreferredQuality ?? 0)",
            "cdn=\(cdnPreference.rawValue)",
            "network=\(environment.networkClass.performanceSampleKey)"
        ].joined(separator: " ")
        PlayerMetricsLog.signpostEvent(
            "VideoDetailStartupBreakdown",
            message: summary
        )
        PlayerMetricsLog.logger.info(
            "startupBreakdown bvid=\(self.detail.bvid, privacy: .public) \(summary, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: detail.bvid,
            title: detail.title,
            message: summary
        )
    }
}

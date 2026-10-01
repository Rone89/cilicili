import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func preparePlayURLLoading(mode: VideoDetailPlayURLLoadMode, traceID: String) {
        playURLState = .loading
        playURLLoadStartTime = CACurrentMediaTime()
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        #if DEBUG
        PlayerMetricsLog.beginStartupTrace(metricsID: detail.bvid, traceID: traceID)
        PlayerMetricsLog.recordStartupTraceEvent(
            metricsID: detail.bvid,
            event: "playURLStart",
            fields: ["cid": String(selectedCID ?? 0), "mode": mode.startMessage]
        )
        let startMessage = "\(mode.startMessage) traceID=\(traceID)"
        #else
        _ = traceID
        let startMessage = mode.startMessage
        #endif
        if mode == .playbackRecovery {
            cancelStartupPlayURLTask()
        }
        PlayerMetricsLog.record(
            .playURLStart,
            metricsID: detail.bvid,
            title: detail.title,
            message: startMessage
        )
    }

    func failPlayURLLoadingForMissingCID() {
        pendingVideoListenPlaybackIntent = nil
        currentPlayURLData = nil
        clearVideoListenAudioVariants()
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        playURLState = .failed("没有找到视频 CID，无法请求播放地址")
    }
}

import Foundation
import KSPlayer
import UIKit

@MainActor
enum PlaybackEngineWarmupCenter {
    private static var didWarmKSPlayerComponents = false

    static func warmKSPlayerComponentsIfNeeded() {
        guard !didWarmKSPlayerComponents else { return }
        didWarmKSPlayerComponents = true

        let startTime = CACurrentMediaTime()
        let options = KSOptions()
        options.registerRemoteControll = false
        options.isSecondOpen = true
        options.isAccurateSeek = false
        options.hardwareDecode = true
        options.asynchronousDecompression = true
        options.preferredForwardBufferDuration = 0.5
        options.maxBufferDuration = 1

        let player = KSMEPlayer(url: URL(fileURLWithPath: "/dev/null"), options: options)
        _ = player.view
        player.pause()
        player.shutdown()

        let elapsed = Int(PlayerMetricsLog.elapsedMilliseconds(since: startTime).rounded())
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: "engineWarmup",
            title: "KSPlayer warmup",
            message: [
                "ksEngineWarmup=components",
                "elapsed=\(elapsed)ms",
                "ffGlobal=\(formatDuration(options.ffmpegGlobalInitDuration))",
                "audioOut=\(formatDuration(options.audioOutputInitDuration))",
                "itemInit=\(formatDuration(options.playerItemInitDuration))",
                "videoOut=\(formatDuration(options.videoOutputInitDuration))",
                "bindOut=\(formatDuration(options.outputBindDuration))"
            ].joined(separator: " ")
        )
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "-" }
        return "\(Int((duration * 1_000).rounded()))ms"
    }
}

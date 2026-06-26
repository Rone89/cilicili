import Foundation

extension PlaybackNetworkPlayerDiagnosticSnapshot {
    @MainActor
    static func primaryRows(
        playerViewModel: PlayerStateViewModel
    ) -> [PlaybackNetworkPlayerDiagnosticRowItem] {
        let diagnostics = playerViewModel.engineDiagnostics
        return [
            PlaybackNetworkPlayerDiagnosticRowItem(title: "状态", value: playerStateTitle(playerViewModel)),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "阶段", value: playerViewModel.playbackPhase.diagnosticTitle),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "引擎", value: diagnostics.engineName),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "解码", value: diagnostics.decodePath.title),
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "异步硬解",
                value: diagnostics.asynchronousDecompressionEnabled ? "开启" : "关闭"
            )
        ]
    }

    @MainActor
    static func playerStateTitle(_ playerViewModel: PlayerStateViewModel) -> String {
        if let errorMessage = playerViewModel.errorMessage, !errorMessage.isEmpty {
            return "播放错误"
        }
        if playerViewModel.isPreparing {
            return "准备中"
        }
        if playerViewModel.isBuffering {
            return "缓冲中"
        }
        if playerViewModel.isPlaying {
            return "播放中"
        }
        return "暂停/待播"
    }
}

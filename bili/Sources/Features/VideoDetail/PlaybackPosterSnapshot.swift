import Foundation

struct PlaybackPosterSnapshot: Equatable {
    var isPlaybackSurfaceReady = false
    var errorMessage: String?
    var loadingProgress = 0.08
    var isBuffering = false

    @MainActor
    init(playerViewModel: PlayerStateViewModel? = nil) {
        guard let playerViewModel else { return }
        isPlaybackSurfaceReady = playerViewModel.isCurrentPlaybackSurfaceReadyForDisplay
        errorMessage = playerViewModel.errorMessage
        loadingProgress = playerViewModel.loadingProgress
        isBuffering = playerViewModel.isBuffering
    }

    var shouldShowPoster: Bool {
        !isPlaybackSurfaceReady && errorMessage == nil
    }

    var isFinishing: Bool {
        loadingProgress >= 0.98
    }

    var loadingMessage: String {
        if isBuffering {
            return "补充缓冲"
        }
        if loadingProgress >= 0.86 {
            return "等待首帧"
        }
        return "准备播放"
    }
}

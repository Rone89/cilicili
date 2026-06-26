import Foundation

struct VideoDetailPlayerActivityBridgeActions {
    let playerViewModel: PlayerStateViewModel
    let onChange: (Bool) -> Void

    func notify() {
        guard !playerViewModel.isTerminated else {
            onChange(false)
            return
        }
        onChange(VideoDetailPlayerActivitySnapshot(playerViewModel: playerViewModel).isActive)
    }

    func notifyInactive() {
        onChange(false)
    }
}

private struct VideoDetailPlayerActivitySnapshot {
    let isActive: Bool

    init(playerViewModel: PlayerStateViewModel) {
        guard ActivePlaybackCoordinator.shared.isActive(playerViewModel) else {
            isActive = false
            return
        }

        if playerViewModel.isPlaying || playerViewModel.isBuffering {
            isActive = true
            return
        }

        switch playerViewModel.playbackPhase {
        case .preparing, .waitingForFirstFrame, .buffering, .seeking, .playing, .recovering:
            isActive = true
        case .idle, .ready, .paused, .ended, .failed:
            isActive = false
        }
    }
}

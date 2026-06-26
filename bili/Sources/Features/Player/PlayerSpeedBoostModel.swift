import Combine
import SwiftUI

@MainActor
final class PlayerSpeedBoostModel: ObservableObject {
    @Published private(set) var isActive = false

    private var state: PlayerSpeedBoostState?

    func beginIfNeeded(
        playerViewModel: PlayerStateViewModel,
        isSurfacePlaying: Bool,
        hidePlaybackControls: () -> Void
    ) {
        guard !playerViewModel.isTerminated else { return }
        guard state == nil else { return }
        let previousRate = playerViewModel.playbackRate
        let wasPlaying = isSurfacePlaying || playerViewModel.isPlaying || playerViewModel.wantsAutoplay
        state = PlayerSpeedBoostState(
            restoredRate: previousRate,
            shouldPauseWhenFinished: !wasPlaying
        )
        isActive = true
        Haptics.medium()
        playerViewModel.recordSpeedBoostMetric("begin restore=\(previousRate.title) wasPlaying=\(wasPlaying)")
        hidePlaybackControls()
        if !wasPlaying {
            playerViewModel.play()
        }
        playerViewModel.setPlaybackRate(.x20)
    }

    func end(
        reason: String,
        playerViewModel: PlayerStateViewModel,
        showPlaybackControls: () -> Void
    ) {
        guard let state else { return }
        self.state = nil
        isActive = false
        guard !playerViewModel.isTerminated else { return }
        playerViewModel.setPlaybackRate(state.restoredRate)
        playerViewModel.stabilizePlaybackAfterSpeedBoost(
            restoredRate: state.restoredRate,
            reason: reason
        )
        if state.shouldPauseWhenFinished {
            playerViewModel.pause()
        }
        showPlaybackControls()
    }

    func cancel() {
        state = nil
        isActive = false
    }
}

private struct PlayerSpeedBoostState: Equatable {
    let restoredRate: BiliPlaybackRate
    let shouldPauseWhenFinished: Bool
}

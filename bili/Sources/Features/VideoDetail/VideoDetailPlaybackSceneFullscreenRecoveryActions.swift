import UIKit

@MainActor
struct VideoDetailPlaybackSceneFullscreenRecoveryActions {
    let context: VideoDetailPlaybackSceneFullscreenActionContext

    func handlePlayerIdentityChanged() {
        guard context.canHandlePlaybackPresentation else {
            context.fullscreenCoordinator.resetForDisappear()
            return
        }
        context.fullscreenCoordinator.restorePortraitWhenInactive()
        retryPendingRotationFullscreenIfNeeded()
    }

    func retryPendingRotationFullscreenIfNeeded() {
        guard context.canHandlePlaybackPresentation else {
            context.fullscreenCoordinator.resetForDisappear()
            return
        }
        let playback = context.playback
        context.fullscreenCoordinator.retryPendingRotationFullscreenIfNeeded(
            currentOrientation: UIDevice.current.orientation,
            playerViewModel: playback.playerViewModel,
            decodePath: playback.decodePath,
            allowsInlineRotation: playback.allowsInlineFullscreenRotation,
            usesPortraitFullscreen: playback.usesPortraitFullscreen,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    func restorePortraitWhenInactive() {
        guard context.canHandlePlaybackPresentation else { return }
        context.fullscreenCoordinator.restorePortraitWhenInactive()
    }

    func resetForDisappear() {
        context.fullscreenCoordinator.resetForDisappear()
    }
}

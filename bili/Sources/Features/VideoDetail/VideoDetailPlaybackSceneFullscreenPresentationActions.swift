import Foundation

@MainActor
struct VideoDetailPlaybackSceneFullscreenPresentationActions {
    let context: VideoDetailPlaybackSceneFullscreenActionContext

    func requestManualFullscreen(_ playerViewModel: PlayerStateViewModel) {
        guard context.canHandlePlaybackPresentation else { return }
        guard context.isCurrentPlayer(playerViewModel) else { return }
        let playback = context.playback
        context.fullscreenCoordinator.enterFullscreen(
            playerViewModel: playerViewModel,
            trigger: .manual,
            allowsInlineRotation: true,
            usesPortraitFullscreen: playback.usesPortraitFullscreen,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }

    func exitFullscreenPlayback() {
        guard context.canHandlePlaybackPresentation else { return }
        let playerViewModel = context.playback.playerViewModel
        context.fullscreenCoordinator.exitFullscreen(
            playerViewModel: playerViewModel,
            isCurrentPlayer: context.isCurrentPlayer
        )
    }
}

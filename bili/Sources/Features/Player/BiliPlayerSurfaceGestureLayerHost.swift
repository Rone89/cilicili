import SwiftUI

struct BiliPlayerSurfaceGestureLayerHost<Content: View>: View {
    let content: Content
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let speedBoostActions: BiliPlayerSpeedBoostActions
    let viewModel: PlayerStateViewModel

    private var gestureActions: BiliPlayerSurfaceGestureActions {
        BiliPlayerSurfaceGestureActions(
            viewModel: viewModel,
            visibilityActions: visibilityActions,
            speedBoostActions: speedBoostActions
        )
    }

    var body: some View {
        BiliPlayerSurfaceGestureLayer(
            content: content,
            onSingleTap: gestureActions.singleTap,
            onDoubleTap: gestureActions.doubleTap,
            onBeginSpeedBoost: gestureActions.beginSpeedBoost,
            onEndSpeedBoost: gestureActions.endSpeedBoost
        )
    }
}

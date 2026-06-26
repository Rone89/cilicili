import SwiftUI

struct VideoDetailToolbarFollowControl: View {
    @ObservedObject var store: VideoDetailInteractionRenderStore
    let canFollow: Bool
    let action: () -> Void

    var body: some View {
        DetailToolbarFollowButton(
            isFollowing: store.interactionState.isFollowing,
            isLoading: store.isMutatingFollow,
            canFollow: canFollow,
            action: action
        )
    }
}

import SwiftUI

struct VideoDetailPlayerPlaceholder: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    let playerWidth: CGFloat?
    let playerHeight: CGFloat

    @State private var isTakingLong = false

    var body: some View {
        let presentation = VideoDetailPlayerPlaceholderPresentation(
            placeholderStore: placeholderStore,
            relatedStore: relatedStore,
            isTakingLong: isTakingLong
        )

        ZStack {
            PlayerLoadingPlaceholder(
                progress: presentation.loadingProgress,
                message: presentation.loadingMessage,
                isFinishing: false,
                secondaryMessage: presentation.secondaryLoadingMessage,
                showsChromeSkeleton: true
            )
            .frame(width: playerWidth)
            .frame(height: playerHeight)
            .task(id: presentation.loadingMessage) {
                await lifecycleActions.watchSlowLoadingIfNeeded(presentation)
            }

            if presentation.showsUnavailableVariantBadge {
                VideoDetailPlayerPlaceholderUnavailableBadge()
            }
        }
        .frame(width: playerWidth)
        .frame(height: playerHeight)
        .background(Color.black)
    }

    private var lifecycleActions: VideoDetailPlayerPlaceholderLifecycleActions {
        VideoDetailPlayerPlaceholderLifecycleActions(isTakingLong: $isTakingLong)
    }
}

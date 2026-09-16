import SwiftUI

@MainActor
struct VideoDetailLoadedDetailContentPageRenderPack {
    let contentWidth: CGFloat
    let pageSelectorStore: VideoDetailPageSelectorRenderStore
    let relatedStore: VideoDetailRelatedRenderStore
    let actions: VideoDetailLoadedDetailContentPageActions

    init(
        viewModel: VideoDetailViewModel,
        layoutWidth: CGFloat,
        horizontalInset: CGFloat
    ) {
        contentWidth = PlaybackDetailContentMetrics.contentWidth(
            for: layoutWidth,
            horizontalInset: horizontalInset
        )
        pageSelectorStore = viewModel.playbackRenderStore.pageSelectorStore
        relatedStore = viewModel.relatedRenderStore
        actions = VideoDetailLoadedDetailContentPageActions(viewModel: viewModel)
    }
}

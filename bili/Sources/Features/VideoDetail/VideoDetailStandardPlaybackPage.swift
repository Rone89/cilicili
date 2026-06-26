import SwiftUI

struct VideoDetailStandardPlaybackPage<DetailContent: View>: View {
    let config: VideoDetailStandardPlaybackPageConfig
    let viewModel: VideoDetailViewModel
    @ObservedObject var playbackStore: VideoDetailPlaybackRenderStore
    @ObservedObject var pageSelectorStore: VideoDetailPageSelectorRenderStore
    @ObservedObject var playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    @Binding var selectedContentTab: VideoDetailContentTab
    let detailContent: (VideoDetailContentTab) -> DetailContent
    @State private var presentationState = VideoDetailStandardPlaybackPagePresentationState()

    var body: some View {
        VideoDetailStandardPlaybackResolvedPage(
            config: config,
            renderPack: resolvedPageRenderPack,
            selectedContentTab: $selectedContentTab,
            isPlaybackActive: $presentationState.header.isPlaybackActive,
            playerIdentityStore: playerIdentityStore,
            onScrollOffsetChange: presentationActions.updateScrollOffset,
            detailContent: detailContent
        )
        .videoDetailStandardPlaybackPageLifecycle(
            isFullscreen: config.isFullscreen,
            scrollState: $presentationState.scroll
        )
    }

    private var resolvedPageRenderPack: VideoDetailStandardPlaybackPageRenderPack {
        VideoDetailStandardPlaybackPageRenderPackBuilder(
            config: config,
            viewModel: viewModel,
            playbackStore: playbackStore,
            pageSelectorStore: pageSelectorStore,
            selectedContentTab: selectedContentTab,
            scrollState: presentationState.scroll
        )
        .renderPack
    }

    private var presentationActions: VideoDetailStandardPlaybackPagePresentationActions {
        VideoDetailStandardPlaybackPagePresentationActions(state: $presentationState)
    }
}

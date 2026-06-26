import Foundation

@MainActor
struct VideoDetailStandardPlaybackPageRenderPackBuilder {
    let config: VideoDetailStandardPlaybackPageConfig
    let viewModel: VideoDetailViewModel
    let playbackStore: VideoDetailPlaybackRenderStore
    let pageSelectorStore: VideoDetailPageSelectorRenderStore
    let selectedContentTab: VideoDetailContentTab
    let scrollState: VideoDetailStandardPlaybackScrollState

    var renderPack: VideoDetailStandardPlaybackPageRenderPack {
        VideoDetailStandardPlaybackPageRenderPack(
            config: config,
            viewModel: viewModel,
            playbackStore: playbackStore,
            pageSelectorStore: pageSelectorStore,
            selectedContentTab: selectedContentTab,
            scrollState: scrollState
        )
    }
}

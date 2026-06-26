import Foundation

@MainActor
struct VideoDetailStandardPlaybackPageRenderPack {
    let context: VideoDetailStandardPlaybackPageContext
    let headerStores: VideoDetailPinnedDynamicPlayerHeaderStores
    let actions: VideoDetailStandardPlaybackPageActions

    init(
        config: VideoDetailStandardPlaybackPageConfig,
        viewModel: VideoDetailViewModel,
        playbackStore: VideoDetailPlaybackRenderStore,
        pageSelectorStore: VideoDetailPageSelectorRenderStore,
        selectedContentTab: VideoDetailContentTab,
        scrollState: VideoDetailStandardPlaybackScrollState
    ) {
        context = Self.makeContext(
            config: config,
            playbackStore: playbackStore,
            pageSelectorStore: pageSelectorStore,
            selectedContentTab: selectedContentTab,
            scrollState: scrollState
        )
        headerStores = Self.makeHeaderStores(viewModel: viewModel)
        actions = Self.makeActions(viewModel: viewModel)
    }

    private static func makeContext(
        config: VideoDetailStandardPlaybackPageConfig,
        playbackStore: VideoDetailPlaybackRenderStore,
        pageSelectorStore: VideoDetailPageSelectorRenderStore,
        selectedContentTab: VideoDetailContentTab,
        scrollState: VideoDetailStandardPlaybackScrollState
    ) -> VideoDetailStandardPlaybackPageContext {
        VideoDetailStandardPlaybackPageContextBuilder(
            config: config,
            selectedPlayVariant: playbackStore.selectedPlayVariant,
            selectedCID: pageSelectorStore.selectedCID,
            pages: pageSelectorStore.pages,
            qualityMenuItems: playbackStore.qualityMenuItems,
            selectedContentTab: selectedContentTab,
            scrollState: scrollState
        ).context
    }

    private static func makeHeaderStores(
        viewModel: VideoDetailViewModel
    ) -> VideoDetailPinnedDynamicPlayerHeaderStores {
        VideoDetailPinnedDynamicPlayerHeaderStoresBuilder(viewModel: viewModel).stores
    }

    private static func makeActions(
        viewModel: VideoDetailViewModel
    ) -> VideoDetailStandardPlaybackPageActions {
        VideoDetailStandardPlaybackPageActions(viewModel: viewModel)
    }
}

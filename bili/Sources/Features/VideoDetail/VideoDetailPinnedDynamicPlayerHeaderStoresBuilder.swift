import Foundation

struct VideoDetailPinnedDynamicPlayerHeaderStoresBuilder {
    let viewModel: VideoDetailViewModel

    var stores: VideoDetailPinnedDynamicPlayerHeaderStores {
        VideoDetailPinnedDynamicPlayerHeaderStores(
            surfaceStore: viewModel.playbackRenderStore.playerSurfaceStore,
            qualityControlStore: viewModel.playbackRenderStore.qualityControlStore,
            placeholderStore: viewModel.playbackRenderStore.placeholderStore,
            relatedStore: viewModel.relatedRenderStore,
            danmakuStore: viewModel.danmakuRenderStore
        )
    }
}

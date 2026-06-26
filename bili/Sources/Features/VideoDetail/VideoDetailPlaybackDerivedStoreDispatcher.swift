import Foundation

@MainActor
struct VideoDetailPlaybackDerivedStoreDispatcher {
    let playerSurfaceStore: VideoDetailPlayerSurfaceRenderStore
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let pageSelectorStore: VideoDetailPageSelectorRenderStore

    func updateStores(with snapshot: VideoDetailPlaybackRenderSnapshot) {
        playerSurfaceStore.update(VideoDetailPlayerSurfaceRenderSnapshot(playback: snapshot))
        qualityControlStore.update(VideoDetailQualityControlRenderSnapshot(playback: snapshot))
        placeholderStore.update(VideoDetailPlayerPlaceholderRenderSnapshot(playback: snapshot))
        pageSelectorStore.update(VideoDetailPageSelectorRenderSnapshot(playback: snapshot))
    }
}

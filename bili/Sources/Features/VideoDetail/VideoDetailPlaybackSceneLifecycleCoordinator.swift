import Foundation

@MainActor
struct VideoDetailPlaybackSceneLifecycleCoordinator {
    let view: VideoDetailPlaybackSceneViewLifecycleActions
    let app: VideoDetailPlaybackSceneAppLifecycleActions
    let playback: VideoDetailPlaybackScenePlaybackLifecycleActions

    init(
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        libraryStore: LibraryStore,
        fullscreenActions: VideoDetailPlaybackSceneFullscreenActions,
        isClosingDetail: @escaping () -> Bool,
        markClosingDetail: @escaping () -> Void
    ) {
        playback = VideoDetailPlaybackScenePlaybackLifecycleActions(
            viewModel: viewModel,
            isClosingDetail: isClosingDetail,
            markClosingDetail: markClosingDetail
        )
        view = VideoDetailPlaybackSceneViewLifecycleActions(
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            fullscreenActions: fullscreenActions,
            playbackActions: playback,
            isClosingDetail: isClosingDetail
        )
        app = VideoDetailPlaybackSceneAppLifecycleActions(
            viewModel: viewModel,
            fullscreenActions: fullscreenActions,
            isClosingDetail: isClosingDetail
        )
    }
}

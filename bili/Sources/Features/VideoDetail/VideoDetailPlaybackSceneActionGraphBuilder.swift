import Foundation

@MainActor
struct VideoDetailPlaybackSceneActionGraphBuilder {
    let dependencies: VideoDetailPlaybackSceneActionDependencies
    let closeCallbacks: VideoDetailPlaybackSceneCloseCallbacks
    let sheetCallbacks: VideoDetailPlaybackSceneSheetCallbacks

    var components: VideoDetailPlaybackSceneActionGraphComponents {
        let fullscreenActions = makeFullscreenActions()
        let sheetActions = makeSheetActions()
        let closeActions = makeCloseActions(fullscreenActions: fullscreenActions)
        let lifecycleActions = makeLifecycleActions(fullscreenActions: fullscreenActions)
        let standardPlaybackActions = makeStandardPlaybackActions(
            fullscreenActions: fullscreenActions,
            closeActions: closeActions,
            sheetActions: sheetActions
        )

        return VideoDetailPlaybackSceneActionGraphComponents(
            fullscreen: fullscreenActions,
            sheets: sheetActions,
            close: closeActions,
            lifecycle: lifecycleActions,
            standardPlayback: standardPlaybackActions
        )
    }

    private func makeFullscreenActions() -> VideoDetailPlaybackSceneFullscreenActions {
        VideoDetailPlaybackSceneFullscreenActions(
            viewModel: dependencies.viewModel,
            fullscreenCoordinator: dependencies.fullscreenCoordinator,
            usesSystemNativePlayerUI: dependencies.usesSystemNativePlayerUI
        )
    }

    private func makeSheetActions() -> VideoDetailPlaybackSceneSheetActions {
        VideoDetailPlaybackSceneSheetActionBuilder(
            callbacks: sheetCallbacks
        ).actions
    }

    private func makeCloseActions(
        fullscreenActions: VideoDetailPlaybackSceneFullscreenActions
    ) -> VideoDetailPlaybackSceneCloseActions {
        VideoDetailPlaybackSceneCloseActionBuilder(
            callbacks: closeCallbacks,
            viewModel: dependencies.viewModel,
            fullscreenActions: fullscreenActions
        ).actions
    }

    private func makeLifecycleActions(
        fullscreenActions: VideoDetailPlaybackSceneFullscreenActions
    ) -> VideoDetailPlaybackSceneLifecycleActions {
        let lifecycleCoordinator = VideoDetailPlaybackSceneLifecycleCoordinator(
            viewModel: dependencies.viewModel,
            runtimeSettings: dependencies.runtimeSettings,
            libraryStore: dependencies.libraryStore,
            fullscreenActions: fullscreenActions,
            isClosingDetail: closeCallbacks.isClosingDetail,
            markClosingDetail: closeCallbacks.markClosingDetail
        )
        return VideoDetailPlaybackSceneHostActionBuilder(
            lifecycleCoordinator: lifecycleCoordinator,
            fullscreenActions: fullscreenActions
        ).lifecycle
    }

    private func makeStandardPlaybackActions(
        fullscreenActions: VideoDetailPlaybackSceneFullscreenActions,
        closeActions: VideoDetailPlaybackSceneCloseActions,
        sheetActions: VideoDetailPlaybackSceneSheetActions
    ) -> VideoDetailStandardPlaybackActions {
        VideoDetailPlaybackSceneStandardPlaybackActionBuilder(
            fullscreenActions: fullscreenActions,
            closeActions: closeActions,
            sheetActions: sheetActions
        ).actions
    }
}

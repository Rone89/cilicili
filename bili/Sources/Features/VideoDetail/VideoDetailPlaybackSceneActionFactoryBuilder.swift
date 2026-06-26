import SwiftUI

@MainActor
struct VideoDetailPlaybackSceneActionFactoryBuilder {
    let viewModel: VideoDetailViewModel
    let fullscreenCoordinator: VideoDetailFullscreenCoordinator
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let libraryStore: LibraryStore
    let usesSystemNativePlayerUI: Bool
    let presentationState: Binding<VideoDetailPlaybackScenePresentationState>
    let bindings: VideoDetailPlaybackSceneBindings
    let onNavigateBack: () -> Void

    var actionFactory: VideoDetailPlaybackSceneActionFactory {
        VideoDetailPlaybackSceneActionFactory(
            dependencies: dependencies,
            closeCallbacks: closeCallbacks,
            sheetCallbacks: sheetCallbacks
        )
    }

    private var dependencies: VideoDetailPlaybackSceneActionDependencies {
        VideoDetailPlaybackSceneActionDependencies(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            usesSystemNativePlayerUI: usesSystemNativePlayerUI
        )
    }

    private var closeCallbacks: VideoDetailPlaybackSceneCloseCallbacks {
        VideoDetailPlaybackSceneCloseCallbacks(
            isClosingDetail: {
                presentationState.wrappedValue.isClosingDetail
                    || viewModel.isPlaybackInvalidatedForNavigation
            },
            markClosingDetail: { presentationState.wrappedValue.isClosingDetail = true },
            onNavigateBack: onNavigateBack
        )
    }

    private var sheetCallbacks: VideoDetailPlaybackSceneSheetCallbacks {
        VideoDetailPlaybackSceneSheetCallbacks(
            showDanmakuSettings: { bindings.isShowingDanmakuSettings.wrappedValue = true },
            showNetworkDiagnostics: { bindings.isShowingNetworkDiagnostics.wrappedValue = true },
            showFavoriteFolders: { bindings.isShowingFavoriteFolders.wrappedValue = true },
            showReplySheet: { comment in bindings.replySheetComment.wrappedValue = comment }
        )
    }
}

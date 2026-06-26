import SwiftUI
import UIKit

struct VideoDetailPlaybackScene: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var replySheetComment: Comment?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void

    @State private var presentationState = VideoDetailPlaybackScenePresentationState()

    private var actionFactory: VideoDetailPlaybackSceneActionFactory {
        VideoDetailPlaybackSceneActionFactoryBuilder(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            libraryStore: dependencies.libraryStore,
            usesSystemNativePlayerUI: isUsingSystemNativePlayerUI,
            presentationState: $presentationState,
            bindings: playbackSceneBindings,
            onNavigateBack: onNavigateBack
        ).actionFactory
    }

    var body: some View {
        VideoDetailPlaybackSceneContent(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            libraryStore: dependencies.libraryStore,
            scenePhase: scenePhase,
            bindings: playbackSceneBindings,
            actions: sceneActions
        )
        .ignoresSafeArea(.container, edges: fullscreenCoordinator.layoutMode != nil ? .all : [])
    }

    private var sceneActions: VideoDetailPlaybackSceneActions {
        actionFactory.actions
    }

    private var playbackSceneBindings: VideoDetailPlaybackSceneBindings {
        VideoDetailPlaybackSceneBindings(
            selectedContentTab: $selectedContentTab,
            replySheetComment: $replySheetComment,
            isShowingDanmakuSettings: $isShowingDanmakuSettings,
            isShowingFavoriteFolders: $isShowingFavoriteFolders,
            isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics
        )
    }

    private var isUsingSystemNativePlayerUI: Bool {
        false
    }
}

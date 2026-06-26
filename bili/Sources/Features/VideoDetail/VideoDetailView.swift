import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    let seedVideo: VideoItem
    private let hidesRootTabBar: Bool
    private let onRequestClose: (() -> Void)?

    @StateObject private var holder = VideoDetailViewModelHolder()
    @StateObject private var runtimeSettings = VideoDetailRuntimeSettingsStore()
    @StateObject private var fullscreenCoordinator = VideoDetailFullscreenCoordinator()
    @State private var presentationState = VideoDetailViewPresentationState()
    @State private var hidesPlayerSystemChrome = false

    init(
        seedVideo: VideoItem,
        hidesRootTabBar: Bool = true,
        onRequestClose: (() -> Void)? = nil
    ) {
        self.seedVideo = seedVideo
        self.hidesRootTabBar = hidesRootTabBar
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VideoDetailViewContent(
            seedVideo: seedVideo,
            holder: holder,
            runtimeSettings: runtimeSettings,
            fullscreenCoordinator: fullscreenCoordinator,
            selectedContentTab: $presentationState.selectedContentTab,
            replySheetComment: $presentationState.replySheetComment,
            isShowingDanmakuSettings: $presentationState.isShowingDanmakuSettings,
            isShowingFavoriteFolders: $presentationState.isShowingFavoriteFolders,
            isShowingNetworkDiagnostics: $presentationState.isShowingNetworkDiagnostics,
            onNavigateBack: dismissVideoDetail,
            lifecycleActions: contentLifecycleActions
        )
        .videoDetailViewChrome(hidesRootTabBar: hidesRootTabBar)
        .statusBar(hidden: hidesPlayerSystemChrome)
        .persistentSystemOverlays(hidesPlayerSystemChrome ? .hidden : .automatic)
        .background {
            VideoDetailChromeStatusBarStyleBridge(
                style: .lightContent,
                isHidden: hidesPlayerSystemChrome
            )
        }
        .onPreferenceChange(VideoDetailChromeHiddenPreferenceKey.self) { isHidden in
            hidesPlayerSystemChrome = isHidden
        }
    }

    private var contentLifecycleActions: VideoDetailViewContentLifecycleActions {
        VideoDetailViewContentLifecycleActions(
            configureViewModel: viewActions.configureViewModel
        )
    }

    private var viewActions: VideoDetailViewActions {
        VideoDetailViewActionsBuilder(
            seedVideo: seedVideo,
            dependencies: dependencies,
            holder: holder,
            fullscreenCoordinator: fullscreenCoordinator,
            dismiss: dismiss,
            onRequestClose: onRequestClose
        )
        .actions
    }

    private func dismissVideoDetail() {
        viewActions.dismissVideoDetail(presentationState: $presentationState)
    }
}

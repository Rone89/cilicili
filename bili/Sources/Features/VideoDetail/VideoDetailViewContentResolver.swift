import SwiftUI

struct VideoDetailViewContentResolver: View {
    let seedVideo: VideoItem
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @ObservedObject var viewModel: VideoDetailViewModel
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var replySheetComment: Comment?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void

    var body: some View {
        VideoDetailLoadedPlaybackContent(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            fullscreenCoordinator: fullscreenCoordinator,
            selectedContentTab: $selectedContentTab,
            replySheetComment: $replySheetComment,
            isShowingDanmakuSettings: $isShowingDanmakuSettings,
            isShowingFavoriteFolders: $isShowingFavoriteFolders,
            isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
            onNavigateBack: onNavigateBack
        )
    }
}

struct VideoDetailInitialContentResolver: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void
    let lifecycleActions: VideoDetailViewContentLifecycleActions

    var body: some View {
        VideoDetailInitialContent(
            seedVideo: seedVideo,
            selectedContentTab: $selectedContentTab,
            runtimeSettings: runtimeSettings,
            onNavigateBack: onNavigateBack
        )
        .task {
            lifecycleActions.configureInitialViewModelIfNeeded()
        }
    }
}

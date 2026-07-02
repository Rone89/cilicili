import SwiftUI

struct VideoDetailViewContentResolver: View {
    @EnvironmentObject private var dependencies: AppDependencies
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
        VideoDetailShellRepresentable(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            selectedContentTab: $selectedContentTab,
            replySheetComment: $replySheetComment,
            isShowingDanmakuSettings: $isShowingDanmakuSettings,
            isShowingFavoriteFolders: $isShowingFavoriteFolders,
            isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
            onNavigateBack: onNavigateBack
        )
        .ignoresSafeArea()
        .videoDetailSheets(
            viewModel: viewModel,
            libraryStore: dependencies.libraryStore,
            sheetState: VideoDetailSheetState(
                replySheetComment: $replySheetComment,
                isShowingFavoriteFolders: $isShowingFavoriteFolders,
                isShowingDanmakuSettings: $isShowingDanmakuSettings,
                isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics
            )
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

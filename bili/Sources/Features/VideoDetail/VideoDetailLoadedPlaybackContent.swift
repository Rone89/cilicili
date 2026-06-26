import SwiftUI

struct VideoDetailLoadedPlaybackContent: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var replySheetComment: Comment?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void

    var body: some View {
        VideoDetailPlaybackScene(
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
    }
}

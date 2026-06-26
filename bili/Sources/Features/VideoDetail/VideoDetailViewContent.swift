import SwiftUI

struct VideoDetailViewContent: View {
    let seedVideo: VideoItem
    @ObservedObject var holder: VideoDetailViewModelHolder
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var replySheetComment: Comment?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void
    let lifecycleActions: VideoDetailViewContentLifecycleActions

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                VideoDetailViewContentResolver(
                    seedVideo: seedVideo,
                    runtimeSettings: runtimeSettings,
                    fullscreenCoordinator: fullscreenCoordinator,
                    viewModel: viewModel,
                    selectedContentTab: $selectedContentTab,
                    replySheetComment: $replySheetComment,
                    isShowingDanmakuSettings: $isShowingDanmakuSettings,
                    isShowingFavoriteFolders: $isShowingFavoriteFolders,
                    isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
                    onNavigateBack: onNavigateBack
                )
            } else {
                VideoDetailInitialContentResolver(
                    seedVideo: seedVideo,
                    selectedContentTab: $selectedContentTab,
                    runtimeSettings: runtimeSettings.snapshot,
                    onNavigateBack: onNavigateBack,
                    lifecycleActions: lifecycleActions
                )
            }
        }
    }
}

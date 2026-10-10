import SwiftUI

struct VideoDetailViewContent: View {
    @State private var commentComposerRequestID = 0
    let seedVideo: VideoItem
    @ObservedObject var holder: VideoDetailViewModelHolder
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var sheetRoute: VideoDetailSheetRoute?
    @Binding var pendingCommentAnchor: VideoCommentAnchor?
    @Binding var hidesSystemChrome: Bool
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingCoinPicker: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void
    let lifecycleActions: VideoDetailViewContentLifecycleActions

    var body: some View {
        PlaybackDetailLoadedStatePage(
            holder.viewModel,
            performanceContext: .video(seedVideo)
        ) { viewModel in
            VideoDetailViewContentResolver(
                seedVideo: seedVideo,
                runtimeSettings: runtimeSettings,
                viewModel: viewModel,
                selectedContentTab: $selectedContentTab,
                sheetRoute: $sheetRoute,
                pendingCommentAnchor: $pendingCommentAnchor,
                hidesSystemChrome: $hidesSystemChrome,
                isShowingDanmakuSettings: $isShowingDanmakuSettings,
                isShowingFavoriteFolders: $isShowingFavoriteFolders,
                isShowingCoinPicker: $isShowingCoinPicker,
                isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
                commentComposerRequestID: commentComposerRequestID,
                onNavigateBack: onNavigateBack
            )
        } initialContent: {
            VideoDetailInitialContentResolver(
                seedVideo: seedVideo,
                selectedContentTab: $selectedContentTab,
                runtimeSettings: runtimeSettings.snapshot,
                lifecycleActions: lifecycleActions
            )
        }
        .environment(\.videoDetailHasOuterBottomBar, true)
        .modifier(VideoDetailBottomToolbarModifier(
            supportsFixedBar: true,
            isHidden: hidesSystemChrome,
            selection: $selectedContentTab,
            onOpenCommentComposer: { commentComposerRequestID += 1 }
        ))
        .environment(\.navigationHistoryBackAction, onNavigateBack)
    }
}

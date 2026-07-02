import SwiftUI

/// 把正式的 UIKit 详情页外壳 `VideoDetailShellViewController` 包回 SwiftUI。
///
/// binding 与回调从 SwiftUI 侧透传，弹窗仍由现有 SwiftUI sheet 承载（挂在
/// 外层 `VideoDetailView`），UIKit 容器只负责通过 binding 置位触发。
struct VideoDetailShellRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var fullscreenCoordinator: VideoDetailFullscreenCoordinator
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var replySheetComment: Comment?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void

    func makeUIViewController(context: Context) -> VideoDetailShellViewController {
        // 新路径绕过 PlaybackScene，需自己 bind runtimeSettings，
        // 否则内容区设置（诊断按钮/进度条等）取默认值。
        runtimeSettings.bind(dependencies.libraryStore)
        return VideoDetailShellViewController(
            viewModel: viewModel,
            fullscreenCoordinator: fullscreenCoordinator,
            runtimeSettings: runtimeSettings,
            dependencies: dependencies,
            selectedContentTab: $selectedContentTab,
            onShowNetworkDiagnostics: { isShowingNetworkDiagnostics = true },
            onShowFavoriteFolders: { isShowingFavoriteFolders = true },
            onShowDanmakuSettings: { isShowingDanmakuSettings = true },
            onReply: { replySheetComment = $0 },
            onNavigateBack: onNavigateBack
        )
    }

    func updateUIViewController(_: VideoDetailShellViewController, context: Context) {}
}

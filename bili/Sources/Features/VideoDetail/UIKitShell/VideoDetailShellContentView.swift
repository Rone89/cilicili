import Combine
import SwiftUI

/// 详情页 UIKit 外壳：竖屏内容区。
///
/// 复用现有 SwiftUI 内容组件（`VideoDetailNativeContentTabView` + 每个 tab 的
/// `VideoDetailContentPage`），不重写。由容器 VC 用 `UIHostingController` 承载。
///
/// 布局对齐原项目「叠放」结构：内容区始终全屏高度，顶部用 `topInset` 留白，
/// 播放器盖在上层收缩。滚动时只有播放器高度变、内容区尺寸不变 → 无反馈抽搐。
struct VideoDetailShellContentView: View {
    @MainActor
    final class State: ObservableObject {
        /// 内容顶部留白 = 播放器最大（expanded）高度。仅在旋转/比例变化时更新，
        /// 滚动时不变（滚动只改播放器实际高度，不动内容区）。
        @Published var topInset: CGFloat = 0
        @Published var scrollAdjustment: VideoDetailScrollAdjustment?
        @Published var suppressesInteractiveContentActions = false
        private var scrollAdjustmentToken = 0

        func requestScrollAdjustment(tab: VideoDetailContentTab, offset: CGFloat) {
            scrollAdjustmentToken += 1
            scrollAdjustment = VideoDetailScrollAdjustment(
                tab: tab,
                offset: offset,
                token: scrollAdjustmentToken
            )
        }
    }

    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var state: State
    let layoutWidth: CGFloat
    @Binding var selectedContentTab: VideoDetailContentTab
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onReply: (Comment) -> Void
    let onSelectedTabChange: (VideoDetailContentTab) -> Void
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void

    var body: some View {
        let contentActionsSuppressed = state.suppressesInteractiveContentActions
        VideoDetailNativeContentTabView(
            selection: $selectedContentTab,
            layoutWidth: layoutWidth,
            topInset: state.topInset,
            scrollAdjustment: state.scrollAdjustment,
            minimizesTabBarOnScroll: runtimeSettings.minimizesTabBarOnScroll,
            onScrollOffsetChange: onScrollOffsetChange,
            content: { tab in
                VideoDetailContentPage(
                    viewModel: viewModel,
                    layoutWidth: layoutWidth,
                    tab: tab,
                    runtimeSettings: runtimeSettings.snapshot,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onReply: { comment in
                        guard !contentActionsSuppressed else { return }
                        onReply(comment)
                    }
                )
            }
        )
        .allowsHitTesting(!contentActionsSuppressed)
        .onChange(of: selectedContentTab) { _, tab in
            onSelectedTabChange(tab)
        }
        .background(VideoDetailTheme.background)
    }
}

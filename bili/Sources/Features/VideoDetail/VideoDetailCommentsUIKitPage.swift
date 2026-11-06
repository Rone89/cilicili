import SwiftUI

/// 评论 UIKit 页面的上下文，由详情页外壳（`VideoDetailNativeContentTabView`）提供。
///
/// 评论页整页由 `UITableView` 承载，列表自身就是滚动容器，因此需要外壳把播放器
/// 收缩所需的留白、底部安全区与滚动回调一并传进来。
@MainActor
struct VideoDetailCommentsPageContext {
    let tab: VideoDetailContentTab
    /// 内容顶部留白 = 播放器展开高度（对应原滚动容器里的首段占位）。
    let topInset: CGFloat
    /// 底部留白（工具栏 + 分段控件）。
    let bottomInset: CGFloat
    /// 播放器可收缩到的最小高度，用于保证内容不足一屏时仍能滚动收起播放器。
    let minimumPlayerHeight: CGFloat
    let standardHorizontalInset: CGFloat
    let isActive: Bool
    /// 底部软边缘（.soft + 工具栏交互），与简介页滚动容器保持一致。
    let showsBottomEdgeEffect: Bool
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
}

/// UIKit 评论页。
///
/// 评论量上千时 SwiftUI `LazyVStack` 会保留所有已构建行并做全量 diff，滚动明显掉帧。
/// 这里把整页换成 `UITableView`（自适应行高 + `UIHostingConfiguration` 承载
/// `CommentRow`），由表格视图充当滚动容器，从而获得真正的 cell 复用：
/// - 内存里只保留可视区域附近的少量行；
/// - 分页由 `UIScrollViewDelegate` 的距底阈值触发，不再依赖 SwiftUI 几何回调；
/// - 行视图仍复用 SwiftUI 实现，点赞、图片、长按菜单、回复预览等交互不变。
@MainActor
struct VideoDetailCommentsUIKitPage: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.commentLikeTarget) private var commentLikeTarget
    @Environment(\.openAppURLAction) private var openAppURL

    let viewModel: VideoDetailViewModel
    let onReply: (Comment) -> Void
    let onComposeReply: ((Comment) -> Void)?
    let context: VideoDetailCommentsPageContext

    var body: some View {
        let renderPack = VideoDetailEmbeddedCommentsSectionRenderPack(
            viewModel: viewModel,
            onReply: onReply,
            onComposeReply: onComposeReply
        )

        VideoDetailCommentsTableViewHost(
            store: renderPack.store,
            actions: renderPack.actions,
            style: .plain,
            horizontalPadding: context.standardHorizontalInset,
            ownerMID: viewModel.detail.owner?.mid,
            cellEnvironment: VideoDetailCommentsCellEnvironment(
                dependencies: dependencies,
                libraryStore: libraryStore,
                appTintColor: appTintColor,
                commentLikeTarget: commentLikeTarget,
                openAppURL: openAppURL
            ),
            context: context
        )
        .commentsSectionLifecycle(
            taskID: renderPack.store.commentsLoadTaskID(autoLoads: true),
            actions: CommentsSectionLifecycleActionsBuilder(
                autoLoads: true,
                beginInitialCommentsLoad: renderPack.actions.beginInitialCommentsLoad
            )
            .actions
        )
        .background(VideoDetailTheme.background)
    }
}

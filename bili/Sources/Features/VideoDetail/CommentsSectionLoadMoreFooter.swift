import SwiftUI

struct CommentsSectionLoadMoreFooter: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let maxVisibleComments: Int?
    let actions: VideoDetailCommentsSectionFooterActions

    init(
        store: VideoDetailCommentsRenderStore,
        maxVisibleComments: Int?,
        loadMoreComments: @escaping () async -> Void
    ) {
        self.store = store
        self.maxVisibleComments = maxVisibleComments
        actions = VideoDetailCommentsSectionFooterActions(loadMoreComments: loadMoreComments)
    }

    var body: some View {
        if store.loadMoreState.isLoading {
            InlineLoadingStateView(title: "正在加载评论")
        } else if case .failed(let message) = store.loadMoreState {
            CommentLoadMoreRetryButton(message: message) {
                actions.retryLoadMoreComments()
            }
        } else if store.hasMoreComments {
            // PiliPlus 式滚动几何触发：只有用户真的滚到列表底部附近（剩余距离 < 700pt）
            // 才自动加载下一页；同时保留点按手动加载。不要用零高度视图 + onAppear 做触发，
            // 也不要依赖视图身份变化——那会形成无节流的分页循环
            // （实测 45 秒拉完 1196 条评论并造成严重掉帧）。
            Label("加载更多评论", systemImage: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await actions.loadMore() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    let viewportBottom = geometry.contentOffset.y + geometry.containerSize.height
                    return geometry.contentSize.height - viewportBottom
                } action: { _, distanceFromEnd in
                    guard distanceFromEnd < 700, !store.loadMoreState.isLoading else { return }
                    Task { await actions.loadMore() }
                }
                .accessibilityIdentifier("comments.loadMore")
        } else {
            Text("没有更多评论了")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }
}

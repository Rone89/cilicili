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
            // 无缝下滑续载：提前 1400pt 预取下一页，用户持续下滑时内容源源不断，
            // 不会看到"点击加载"的按钮。不要改回零高度视图 + onAppear 的触发方式，
            // 也不要依赖视图身份变化——那会形成无节流的分页循环
            // （实测 45 秒拉完 1196 条评论并造成严重掉帧）。
            Text("继续下滑加载更多评论")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                    guard distanceFromEnd < 1400, !store.loadMoreState.isLoading else { return }
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

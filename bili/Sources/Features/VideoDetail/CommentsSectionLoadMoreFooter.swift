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
            // 无缝下滑续载：三路触发。
            // 1) onAppear：footer 被构建（进入视口/预取范围）时加载 —— 覆盖"已经滚到底、
    //        没有后续滚动帧"的场景（onScrollGeometryChange 只在值变化时回调，到底后
    //        不再触发）；
            // 2) onScrollGeometryChange：footer 已在屏上、用户继续下滑时提前预取；
            // 3) onTapGesture：手动兜底。
            // 注意：不要给本视图加 `.id(...)`，也不要改回零高度常驻视图——每次分页后
            // 身份重建会重触发 onAppear，形成无节流分页循环（实测拉完 1196 条评论）。
            // VM 层另有 800ms 节流 + 总数判尾兜底。
            Text("继续下滑加载更多评论")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onAppear {
                    Task { await actions.loadMore() }
                }
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

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
            // PiliPlus 式滚动触发：footer 有真实高度和稳定身份，只有滚到底部进入视口
            // 才触发一次加载。不要给这个视图加 `.id(...)` 或改成零高度常驻视图——
            // 那会让 onAppear 在每次分页后重新触发，形成无节流的分页循环
            // （实测 45 秒拉完 1196 条评论并造成严重掉帧）。
            Label("加载更多评论", systemImage: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onAppear {
                    Task { await actions.loadMore() }
                }
                .onTapGesture {
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

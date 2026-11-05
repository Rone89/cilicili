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
            // 失败态保留几何观察：用户继续下滑时自动重试（VM 层 800ms 节流防风暴）。
            // 没有它，失败后 footer 的触发器会随视图一起消失，只能手动点。
            CommentLoadMoreAutoRetryTrigger(
                store: store,
                loadMore: {
                    Task { await actions.loadMore() }
                }
            )
        } else if store.hasMoreComments {
            // 无缝下滑续载：观察 footer 自身的全局坐标（onGeometryChange 对任何滚动
            // 容器都有效，不依赖 onAppear 生命周期 / onScrollGeometryChange 的滚动祖先
            // 解析——前两者在本页 LazyVStack 上实测均不可靠）。footer 进入屏幕可视范围
            // 即自动加载；VM 层 800ms 节流 + 总数判尾兜底防失控。
            // 不要加 onAppear：它会与几何触发在打开时双双命中，连拉两页易触发风控。
            Text("继续下滑加载更多评论")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await actions.loadMore() }
                }
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { _, frame in
                    guard let screenHeight = Self.visibleScreenHeight() else { return }
                    // footer 顶边进入屏幕底部 300pt 缓冲区即视为"接近底部"。
                    let isNearViewport = frame.minY < screenHeight + 300
                    guard isNearViewport, frame.maxY > 0, !store.loadMoreState.isLoading else { return }
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

    private static func visibleScreenHeight() -> CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .bounds.height
    }
}

/// 失败态下的自动重试触发器：观察 footer 全局坐标，用户下滑使其重新进入可视
/// 范围时自动重试（受 VM 层 800ms 节流约束，不会产生请求风暴）。
private struct CommentLoadMoreAutoRetryTrigger: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let loadMore: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { _, frame in
                guard let screenHeight = Self.visibleScreenHeight() else { return }
                let isNearViewport = frame.minY < screenHeight + 300
                guard isNearViewport, frame.maxY > 0, !store.loadMoreState.isLoading else { return }
                loadMore()
            }
    }

    private static func visibleScreenHeight() -> CGFloat? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .bounds.height
    }
}

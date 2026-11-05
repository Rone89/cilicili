import Foundation
import QuartzCore

extension VideoDetailViewModel {
    /// 评论分页最小间隔：视图层可能被多种路径触发（onAppear/滚动几何/点按），
    /// 数据层用时间节流兜底，保证任何触发风暴下最多每 800ms 发起一页。
    private var lastCommentPageLoadStartedAt: CFTimeInterval {
        get { commentListState.lastPageLoadStartedAt }
        set { commentListState.lastPageLoadStartedAt = newValue }
    }

    func loadMoreComments() async {
        guard !commentState.isLoading,
              !commentLoadMoreState.isLoading,
              !commentsEnd
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastCommentPageLoadStartedAt >= 0.8 else { return }
        // 对齐 PiliPlus：用服务端返回的评论总数提前判尾，加载量达到总数后不再发请求。
        if let totalReplyCount = detail.stat?.reply, totalReplyCount > 0,
           comments.count >= totalReplyCount {
            commentsEnd = true
            return
        }
        lastCommentPageLoadStartedAt = now
        await loadCommentsPage(presentsErrors: false, emptyPageSkipLimit: 2)
    }

    func retryComments() async {
        cancelCommentsLoadingTask()
        await loadInitialComments()
    }

    func selectCommentSort(_ sort: CommentSort) async {
        guard selectedCommentSort != sort else { return }
        selectedCommentSort = sort
        cancelCommentsLoadingTask()
        await loadInitialComments()
    }

}

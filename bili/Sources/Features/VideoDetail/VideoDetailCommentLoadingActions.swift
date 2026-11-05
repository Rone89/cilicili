import Foundation

extension VideoDetailViewModel {
    func loadMoreComments() async {
        guard !commentState.isLoading,
              !commentLoadMoreState.isLoading,
              !commentsEnd
        else { return }
        // 对齐 PiliPlus：用服务端返回的评论总数提前判尾，加载量达到总数后不再发请求。
        if let totalReplyCount = detail.stat?.reply, totalReplyCount > 0,
           comments.count >= totalReplyCount {
            commentsEnd = true
            return
        }
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

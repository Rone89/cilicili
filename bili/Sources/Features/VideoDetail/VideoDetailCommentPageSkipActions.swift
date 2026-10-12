import Foundation

extension VideoDetailViewModel {
    func shouldSkipEmptyCommentPage(
        previousCount: Int,
        previousCursor: String,
        remainingEmptyPageSkips: Int
    ) -> Bool {
        let didAppendComments = comments.count > previousCount
        return !didAppendComments
            && !commentsEnd
            && remainingEmptyPageSkips > 0
            && !commentCursor.isEmpty
            && commentCursor != previousCursor
    }

    func finishCommentPageLoadWithoutSkip(previousCount: Int, previousCursor: String) {
        let didAppendComments = comments.count > previousCount
        if !commentsEnd,
           commentCursor.isEmpty || commentCursor == previousCursor || !didAppendComments {
            if commentCursor.isEmpty { commentCursor = previousCursor }
            commentLoadMoreState = .failed("评论分页暂未推进，点击继续加载")
        }
    }

    func continueCommentPageLoadAfterEmptySkip(isLoadingMore: Bool) {
        if isLoadingMore {
            commentLoadMoreState = .loading
        } else {
            commentState = .loading
        }
    }
}

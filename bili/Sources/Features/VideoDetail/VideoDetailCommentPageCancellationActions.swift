import Foundation

extension VideoDetailViewModel {
    func resetCommentStateAfterCancellation(isInitialPage: Bool, wasLoadingMore: Bool) {
        if comments.isEmpty, isInitialPage, !didCompleteInitialCommentLoad {
            commentState = .idle
        } else {
            commentState = .loaded
        }
        commentLoadMoreState = wasLoadingMore
            ? .failed("评论加载已中断，点击重试") : .idle
    }
}

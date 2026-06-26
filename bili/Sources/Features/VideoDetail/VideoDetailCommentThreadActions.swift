import Foundation

extension VideoDetailViewModel {
    func replies(for comment: Comment) -> [Comment] {
        replyThreads[comment.id] ?? comment.replies ?? []
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        replyThreadStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard replyThreads[comment.id] == nil else { return }
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        replyThreads[comment.id] = nil
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard replyThreadHasMore[comment.id] != false,
              !(replyThreadStates[comment.id]?.isLoading ?? false) else { return }
        await loadReplyPage(for: comment, reset: false)
    }
}

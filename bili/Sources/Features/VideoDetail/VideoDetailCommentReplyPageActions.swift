import Foundation

extension VideoDetailViewModel {
    func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let target = commentTarget else {
            replyThreadStates[comment.id] = .failed("没有找到评论对象，无法加载回复")
            return
        }
        let token = beginReplyThreadLoad(for: comment.id)
        defer {
            clearReplyThreadLoadIfCurrent(commentID: comment.id, token: token)
        }
        replyThreadStates[comment.id] = .loading
        do {
            let nextPage = reset ? 1 : (replyThreadPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(
                oid: target.oid,
                type: target.type,
                root: comment.rpid,
                page: nextPage
            )
            guard isCurrentReplyThreadLoad(commentID: comment.id, token: token, target: target) else {
                return
            }
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            replyThreads[comment.id] = replies
            replyThreadPages[comment.id] = nextPage
            replyThreadHasMore[comment.id] = page.hasMoreReplyPages(requestedPage: nextPage)
            replyThreadStates[comment.id] = .loaded
        } catch {
            guard isCurrentReplyThreadLoad(commentID: comment.id, token: token, target: target) else {
                return
            }
            if reset {
                replyThreads[comment.id] = filteredComments(comment.replies ?? [])
            }
            // Preserve the last successful page so retry requests the same next page.
            replyThreadStates[comment.id] = .failed(error.localizedDescription)
        }
    }
}

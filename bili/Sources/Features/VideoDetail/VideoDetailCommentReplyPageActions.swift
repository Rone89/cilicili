import Foundation

extension VideoDetailViewModel {
    func loadReplyPage(for comment: Comment, reset: Bool) async {
        guard let aid = detail.aid else {
            replyThreadStates[comment.id] = .failed("没有找到视频 AV 号，无法加载回复")
            return
        }
        let bvid = detail.bvid
        let token = beginReplyThreadLoad(for: comment.id)
        defer {
            clearReplyThreadLoadIfCurrent(commentID: comment.id, token: token)
        }
        replyThreadStates[comment.id] = .loading
        do {
            let nextPage = reset ? 1 : (replyThreadPages[comment.id] ?? 1) + 1
            let page = try await api.fetchCommentReplies(aid: aid, root: comment.rpid, page: nextPage)
            guard isCurrentReplyThreadLoad(commentID: comment.id, token: token, aid: aid, bvid: bvid) else {
                return
            }
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(existingReplies + fetchedReplies)
            replyThreads[comment.id] = replies
            replyThreadPages[comment.id] = nextPage
            let totalCount = comment.replyCount ?? Int.max
            replyThreadHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
            replyThreadStates[comment.id] = .loaded
        } catch {
            guard isCurrentReplyThreadLoad(commentID: comment.id, token: token, aid: aid, bvid: bvid) else {
                return
            }
            if reset {
                let fallbackReplies = filteredComments(comment.replies ?? [])
                replyThreads[comment.id] = fallbackReplies
                if fallbackReplies.isEmpty {
                    replyThreadStates[comment.id] = .failed(error.localizedDescription)
                } else {
                    replyThreadHasMore[comment.id] = false
                    replyThreadStates[comment.id] = .loaded
                }
            } else {
                replyThreadHasMore[comment.id] = false
                replyThreadStates[comment.id] = .loaded
            }
        }
    }
}

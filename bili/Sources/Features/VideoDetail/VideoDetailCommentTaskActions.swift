import Foundation

extension VideoDetailViewModel {
    func cancelCommentsLoadingTask(advancesGeneration: Bool = true) {
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        commentsLoadingToken = nil
        if advancesGeneration {
            advanceCommentPageLoadGeneration()
        }
    }

    func clearCommentThreadLoads() {
        replyThreadLoadTokens.removeAll()
        dialogThreadLoadTokens.removeAll()
    }

    func clearCommentThreadCaches() {
        replyThreads = [:]
        replyThreadStates = [:]
        replyThreadPages = [:]
        replyThreadHasMore = [:]
        dialogThreads = [:]
        dialogThreadStates = [:]
    }

    func resetCommentThreadStateForNewComments() {
        clearCommentThreadLoads()
        clearCommentThreadCaches()
    }

    @discardableResult
    func beginReplyThreadLoad(for commentID: Int) -> UUID {
        let token = UUID()
        replyThreadLoadTokens[commentID] = token
        return token
    }

    func isCurrentReplyThreadLoad(
        commentID: Int,
        token: UUID,
        aid: Int,
        bvid: String
    ) -> Bool {
        replyThreadLoadTokens[commentID] == token
            && comments.contains { $0.id == commentID }
            && isCurrentVideoContext(aid: aid, bvid: bvid)
    }

    func clearReplyThreadLoadIfCurrent(commentID: Int, token: UUID) {
        guard replyThreadLoadTokens[commentID] == token else { return }
        replyThreadLoadTokens[commentID] = nil
    }

    @discardableResult
    func beginDialogThreadLoad(for key: String) -> UUID {
        let token = UUID()
        dialogThreadLoadTokens[key] = token
        return token
    }

    func isCurrentDialogThreadLoad(
        key: String,
        rootID: Int,
        token: UUID,
        aid: Int,
        bvid: String
    ) -> Bool {
        dialogThreadLoadTokens[key] == token
            && comments.contains { $0.id == rootID }
            && isCurrentVideoContext(aid: aid, bvid: bvid)
    }

    func clearDialogThreadLoadIfCurrent(key: String, token: UUID) {
        guard dialogThreadLoadTokens[key] == token else { return }
        dialogThreadLoadTokens[key] = nil
    }
}

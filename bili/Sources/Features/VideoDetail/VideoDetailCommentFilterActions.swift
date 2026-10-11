import Foundation

extension VideoDetailViewModel {
    func appendUniqueComments(_ more: [Comment]) {
        if commentListState.usesLoadingRecovery {
            var seen = Set(comments.map(\.id))
            comments.append(contentsOf: more.filter { seen.insert($0.id).inserted })
            return
        }
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    func filteredComments(_ values: [Comment]) -> [Comment] {
        guard libraryStore.blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    func refilterLoadedComments() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        if libraryStore.blocksGoodsComments {
            comments = filteredComments(comments)
            replyThreads = replyThreads.mapValues(filteredComments)
            dialogThreads = dialogThreads.mapValues(filteredComments)
        } else {
            let reloadTask = Task { @MainActor [weak self] in
                guard let self, !self.isPlaybackInvalidatedForNavigation else { return }
                await self.reloadCommentRelatedData()
            }
            trackBackgroundTask(reloadTask)
        }
    }

    func reloadCommentRelatedData() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        await loadInitialComments()
    }

    func refilterLoadedCommentsForRecovery(blocksGoodsComments: Bool) {
        // @Published sends before LibraryStore stores the new value.
        if blocksGoodsComments {
            comments = comments.filter { !$0.containsGoodsPromotion }
            replyThreads = replyThreads.mapValues { $0.filter { !$0.containsGoodsPromotion } }
            dialogThreads = dialogThreads.mapValues { $0.filter { !$0.containsGoodsPromotion } }
        }
        scheduleCommentRecoveryReload()
    }

    func scheduleCommentRecoveryReload() {
        cancelCommentsLoadingTask()
        clearCommentThreadLoads()
        let anchor = commentThreadState.deepLinkAnchor
        clearCommentThreadCaches()
        commentThreadState.deepLinkAnchor = anchor
        commentListState.needsThreadRecoveryReload = true
        let generation = commentPageLoadGeneration
        let reloadTask = Task { @MainActor [weak self] in
            guard let self, !self.isPlaybackInvalidatedForNavigation,
                  self.commentPageLoadGeneration == generation else { return }
            await self.loadInitialComments()
        }
        trackBackgroundTask(reloadTask)
    }

    func dialogKey(root: Comment, reply: Comment) -> String {
        VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
    }

    func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        VideoDetailCommentThreadResolver.localDialogReplies(
            reply, siblings: replies(for: root), includesParent: commentListState.usesLoadingRecovery
        )
    }

    func uniqueComments(_ comments: [Comment]) -> [Comment] {
        VideoDetailCommentThreadResolver.uniqueComments(comments)
    }
}

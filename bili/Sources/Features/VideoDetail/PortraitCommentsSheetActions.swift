import Foundation

struct PortraitCommentsSheetActions {
    let beginInitialCommentsLoad: () -> Void
    let selectCommentSort: (CommentSort) async -> Void
    let retryComments: () async -> Void
    let loadMoreComments: () async -> Void
    let replies: PortraitCommentsSheetReplyActions

    @MainActor
    func selectCommentSortAction(_ sort: CommentSort) {
        Task { await selectCommentSort(sort) }
    }

    @MainActor
    func retryCommentsAction() {
        Task { await retryComments() }
    }

    @MainActor
    func loadMoreCommentsAction() {
        Task { await loadMoreComments() }
    }
}

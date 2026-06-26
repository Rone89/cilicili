import Foundation

struct PortraitCommentsSheetReplyActions {
    let loadReplies: (Comment) async -> Void
    let reloadReplies: (Comment) async -> Void
    let loadMoreReplies: (Comment) async -> Void
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void

    @MainActor
    func loadMoreRepliesAction(_ comment: Comment) {
        Task { await loadMoreReplies(comment) }
    }
}

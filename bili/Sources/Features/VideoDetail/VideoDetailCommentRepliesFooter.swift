import SwiftUI

struct CommentRepliesFooter: View {
    let snapshot: VideoDetailCommentThreadRepliesSnapshot
    let actions: CommentRepliesFooterActions

    init(
        snapshot: VideoDetailCommentThreadRepliesSnapshot,
        rootComment: Comment,
        loadMoreReplies: @escaping (Comment) async -> Void
    ) {
        self.snapshot = snapshot
        actions = CommentRepliesFooterActions(
            rootComment: rootComment,
            loadMoreReplies: loadMoreReplies
        )
    }

    var body: some View {
        if snapshot.hasLoadedReplies, snapshot.state.isLoading {
            InlineLoadingStateView(title: "加载更多回复")
        } else if case .failed(let message) = snapshot.state {
            CommentErrorView(message: message) {
                actions.performLoadMoreReplies()
            }
        } else if snapshot.hasMoreReplies {
            Button {
                actions.performLoadMoreReplies()
            } label: {
                Label("查看更多回复", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
    }
}

import SwiftUI

struct DynamicCommentsListContent: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let showReplies: (Comment) -> Void

    @ViewBuilder
    var body: some View {
        if !viewModel.canLoadComments {
            EmptyStateView(title: "暂不支持评论", systemImage: "bubble.left", message: "这条动态没有返回评论入口。")
                .padding(16)
        } else if viewModel.comments.isEmpty && viewModel.state.isLoading {
            CommentLoadingSkeletonList(count: 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else if viewModel.comments.isEmpty, case .failed(let message) = viewModel.state {
            DynamicCommentErrorView(message: message) {
                Task { await viewModel.reload() }
            }
            .padding(14)
        } else if viewModel.comments.isEmpty {
            DynamicCommentPlainEmptyStateView(
                title: "暂无评论",
                systemImage: "bubble.left",
                message: "这里还没有可展示的评论。"
            )
            .padding(14)
        } else {
            DynamicCommentsLoadedList(viewModel: viewModel, showReplies: showReplies)
        }
    }
}

private struct DynamicCommentsLoadedList: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let showReplies: (Comment) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.commentItems) { item in
                DynamicCommentRow(item: item) {
                    showReplies(item.comment)
                }
                .padding(.horizontal, 14)

                Divider()
                    .padding(.leading, 62)
            }

            DynamicCommentsFooter(viewModel: viewModel)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
}

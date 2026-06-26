import SwiftUI

struct DynamicCommentsSheetContent: View {
    let item: DynamicFeedItem
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let showReplies: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DynamicCommentsHeader(
                replyCount: item.replyCount,
                selectedSort: Binding(
                    get: { viewModel.selectedSort },
                    set: { sort in
                        Task { await viewModel.selectSort(sort) }
                    }
                )
            )
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)

            DynamicCommentsListContent(viewModel: viewModel, showReplies: showReplies)
        }
    }
}

import SwiftUI

struct PortraitCommentsSheetCommentRows: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let actions: PortraitCommentsSheetActions
    @Binding var replySheetComment: Comment?

    var body: some View {
        if store.comments.isEmpty && (store.state.isLoading || store.state == .idle) {
            PortraitCommentsSheetLoadingRows()
        } else if store.comments.isEmpty, case .failed(let message) = store.state {
            PortraitCommentsSheetErrorRow(message: message) {
                actions.retryCommentsAction()
            }
        } else if store.shouldShowEmptyCommentsState {
            PortraitCommentsSheetEmptyRow()
        } else if store.shouldShowCommentReloadPrompt {
            PortraitCommentsSheetErrorRow(message: "评论暂时没有返回内容") {
                actions.retryCommentsAction()
            }
        } else {
            let commentItems = store.commentItems
            ForEach(commentItems) { item in
                CommentRow(
                    item: item,
                    style: .plain,
                    showReplies: {
                        replySheetComment = item.comment
                    }
                )
                .equatable()
                .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Divider()
                    .padding(.leading, 58)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowBackground(Color.clear)
            }

            PortraitCommentsSheetFooterRow(store: store, actions: actions)
        }
    }
}

import SwiftUI

struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    let replyStore: DynamicCommentReplyStore
    @State private var dialogReply: Comment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentRepliesContent(rootComment: rootComment, replyStore: replyStore) { reply in
                        dialogReply = reply
                    }
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: false)
            .task {
                await replyStore.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(rootComment: rootComment, focusReply: reply, replyStore: replyStore)
        }
    }
}

private struct DynamicCommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let replyStore: DynamicCommentReplyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentDialogContent(rootComment: rootComment, focusReply: focusReply, replyStore: replyStore)
                }
            }
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: false)
            .task {
                await replyStore.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}

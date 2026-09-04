import SwiftUI

struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    var submitReply: ((DynamicCommentComposerTarget, String) async throws -> Void)? = nil
    @State private var dialogReply: Comment?
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var commentDrafts = [String: String]()

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(
                        comment: rootComment,
                        reply: submitReply == nil ? nil : {
                            composerTarget = .reply(root: rootComment, parent: rootComment)
                        }
                    )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentRepliesContent(
                        rootComment: rootComment,
                        replyStore: replyStore,
                        highlightedReplyID: nil,
                        showDialog: { reply in
                            dialogReply = reply
                        },
                        replyToComment: submitReply == nil ? nil : { reply in
                            composerTarget = .reply(root: rootComment, parent: reply)
                        }
                    )
                }
            }
            .defersRemoteImageLoadsDuringFastScroll()
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadReplies(for: rootComment)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
        .sheet(item: $dialogReply) { reply in
            DynamicCommentDialogSheet(rootComment: rootComment, focusReply: reply, replyStore: replyStore)
        }
        .sheet(item: $composerTarget) { target in
            DynamicCommentComposerSheet(
                draft: commentDraftBinding(for: target),
                target: target,
                submit: { message in
                    guard let submitReply else { return }
                    try await submitReply(target, message)
                    await replyStore.reloadReplies(for: rootComment)
                }
            )
        }
    }

    private func commentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<String> {
        Binding(
            get: { commentDrafts[target.id] ?? "" },
            set: { commentDrafts[target.id] = $0 }
        )
    }
}

private struct DynamicCommentDialogSheet: View {
    let rootComment: Comment
    let focusReply: Comment
    let replyStore: DynamicCommentReplyStore

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(comment: rootComment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider()

                    DynamicCommentDialogContent(
                        rootComment: rootComment,
                        focusReply: focusReply,
                        replyStore: replyStore
                    )
                }
            }
            .defersRemoteImageLoadsDuringFastScroll()
            .hiddenInlineNavigationTitle()
            .nativeTopScrollEdgeEffect()
            .task {
                await replyStore.loadDialog(for: rootComment, reply: focusReply)
            }
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
}

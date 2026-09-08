import SwiftUI

struct DynamicCommentRepliesSheet: View {
    let rootComment: Comment
    @ObservedObject var replyStore: DynamicCommentReplyStore
    let api: BiliAPIClient
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    @State private var dialogReply: Comment?
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var richCommentDrafts = [String: RichCommentDraft]()

    var body: some View {
        CommentOwnerProfileNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DynamicCommentReplyRootView(
                        comment: rootComment,
                        reply: {
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
                        replyToComment: { reply in
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
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: richCommentDraftBinding,
                api: api,
                submit: { submissionTarget, message, pictures in
                    try await submitReply(submissionTarget, message, pictures)
                    await replyStore.reloadReplies(for: rootComment)
                }
            )
            .allowsHitTesting(false)
        }
    }

    private func richCommentDraftBinding(for target: DynamicCommentComposerTarget) -> Binding<RichCommentDraft> {
        Binding(
            get: { richCommentDrafts[target.id] ?? RichCommentDraft(replyTarget: target) },
            set: { richCommentDrafts[target.id] = $0 }
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

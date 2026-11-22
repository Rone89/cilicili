import Combine
import SwiftUI

struct VideoDetailSplitSelectionSheetPayload: Identifiable {
    let id = UUID()
    let sectionTitle: String
    let items: [VideoDetailCompactSelectionItem]
    let selectItem: (VideoDetailCompactSelectionItem) -> Void
}

struct VideoDetailSplitCommentDialogPayload: Identifiable {
    let id = UUID()
    let rootComment: Comment
    let focusReply: Comment
    let store: VideoDetailCommentThreadRenderStore
    let loadDialog: (Comment, Comment) async -> Void
    let reloadDialog: (Comment, Comment) async -> Void
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
}

struct VideoDetailSplitInlineComposerPayload {
    let ownerID: ObjectIdentifier
    let targetID: String
    let content: AnyView
    let onDismiss: () -> Void
}

/// Coordinates modal presentations scoped strictly to the right-hand detail/comments
/// column while `VideoDetailSwiftUIContainer` is in landscape `.twoColumnSplit`,
/// ensuring popups never cover the left-hand video player.
@MainActor
final class VideoDetailSplitColumnOverlayController: ObservableObject {
    @Published var isSplitColumnMode = false
    @Published var selectionSheet: VideoDetailSplitSelectionSheetPayload?
    @Published var commentDialogSheet: VideoDetailSplitCommentDialogPayload?
    @Published var inlineComposer: VideoDetailSplitInlineComposerPayload?

    func setSplitColumnMode(_ active: Bool) {
        guard isSplitColumnMode != active else { return }
        isSplitColumnMode = active
        if !active {
            dismissAll()
        }
    }

    func presentInlineComposer(
        ownerID: ObjectIdentifier,
        targetID: String,
        content: AnyView,
        onDismiss: @escaping () -> Void
    ) {
        inlineComposer = VideoDetailSplitInlineComposerPayload(
            ownerID: ownerID,
            targetID: targetID,
            content: content,
            onDismiss: onDismiss
        )
    }

    func dismissInlineComposerIfOwned(by ownerID: ObjectIdentifier) {
        guard inlineComposer?.ownerID == ownerID else { return }
        inlineComposer = nil
    }

    func dismissAll() {
        selectionSheet = nil
        commentDialogSheet = nil
        if let composer = inlineComposer {
            inlineComposer = nil
            composer.onDismiss()
        }
    }
}

extension EnvironmentValues {
    @Entry var videoDetailSplitColumnOverlay: VideoDetailSplitColumnOverlayController? = nil
    @Entry var videoDetailSplitSheetDismiss: (() -> Void)? = nil
}

/// Renders comment threads, nested reply dialogs, comment composers, and episode/page
/// selectors strictly inside the right-hand detail/comments column frame.
struct VideoDetailSplitColumnSheetHost: View {
    @ObservedObject var overlay: VideoDetailSplitColumnOverlayController
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    @Binding var sheetRoute: VideoDetailSheetRoute?
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void

    private var commentThreadPresentation: VideoDetailCommentThreadSheetPresentation? {
        guard case .commentThread(let presentation) = sheetRoute else { return nil }
        return presentation
    }

    private var videoReferer: String {
        let bvid = viewModel.detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        return bvid.isEmpty ? "https://www.bilibili.com" : "https://www.bilibili.com/video/\(bvid)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let selection = overlay.selectionSheet {
                VideoDetailSplitSheetCard(
                    heightFraction: 0.74,
                    onDismiss: { overlay.selectionSheet = nil }
                ) {
                    VideoDetailCompactSelectionSheet(
                        sectionTitle: selection.sectionTitle,
                        items: selection.items,
                        selectItem: selection.selectItem
                    )
                    .environment(\.videoDetailSplitSheetDismiss) {
                        overlay.selectionSheet = nil
                    }
                }
                .id(selection.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            if let presentation = commentThreadPresentation {
                VideoDetailSplitSheetCard(
                    heightFraction: 0.88,
                    onDismiss: dismissCommentThread
                ) {
                    commentThreadContent(for: presentation)
                        .environment(\.videoDetailSplitSheetDismiss, dismissCommentThread)
                        .environment(\.videoDetailSplitColumnOverlay, overlay)
                        .environment(
                            \.videoDetailStandardHorizontalInset,
                            libraryStore.standardPageHorizontalInset
                        )
                        .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
                        .commentLikeTarget(
                            oid: viewModel.commentTarget?.oid,
                            type: viewModel.commentTarget?.type,
                            referer: videoReferer
                        )
                }
                .id(presentation.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            if let dialog = overlay.commentDialogSheet {
                VideoDetailSplitSheetCard(
                    heightFraction: 0.88,
                    onDismiss: { overlay.commentDialogSheet = nil }
                ) {
                    CommentDialogSheet(
                        rootComment: dialog.rootComment,
                        focusReply: dialog.focusReply,
                        store: dialog.store,
                        loadDialog: dialog.loadDialog,
                        reloadDialog: dialog.reloadDialog,
                        submitReply: dialog.submitReply
                    )
                    .environment(\.videoDetailSplitSheetDismiss) {
                        overlay.commentDialogSheet = nil
                    }
                    .environment(\.videoDetailSplitColumnOverlay, overlay)
                    .environment(
                        \.videoDetailStandardHorizontalInset,
                        libraryStore.standardPageHorizontalInset
                    )
                    .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
                    .commentLikeTarget(
                        oid: viewModel.commentTarget?.oid,
                        type: viewModel.commentTarget?.type,
                        referer: videoReferer
                    )
                }
                .id(dialog.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            if let composer = overlay.inlineComposer {
                composer.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .animation(.smooth(duration: 0.24), value: overlay.selectionSheet?.id)
        .animation(.smooth(duration: 0.24), value: commentThreadPresentation?.id)
        .animation(.smooth(duration: 0.24), value: overlay.commentDialogSheet?.id)
        .animation(.easeOut(duration: 0.16), value: overlay.inlineComposer?.targetID)
    }

    @ViewBuilder
    private func commentThreadContent(
        for presentation: VideoDetailCommentThreadSheetPresentation
    ) -> some View {
        let actions = VideoDetailSheetActions(viewModel: viewModel)
        let comment = presentation.rootComment
        if let replyID = presentation.secondaryID,
           let reply = viewModel.replies(for: comment).first(where: { $0.id == replyID }) {
            CommentDialogSheet(
                rootComment: comment,
                focusReply: reply,
                store: viewModel.commentThreadRenderStore,
                loadDialog: actions.replies.loadDialog,
                reloadDialog: actions.replies.reloadDialog,
                submitReply: submitReply
            )
        } else {
            VideoDetailReplySheetHost(
                rootComment: comment,
                viewModel: viewModel,
                initialReplyID: nil,
                actions: actions.replies,
                submitReply: submitReply
            )
        }
    }

    private func dismissCommentThread() {
        overlay.commentDialogSheet = nil
        viewModel.clearDeepLinkCommentThreadAnchor()
        if case .commentThread = sheetRoute {
            sheetRoute = nil
        }
    }
}

private struct VideoDetailSplitSheetCard<Content: View>: View {
    let heightFraction: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = max(280, (proxy.size.height * heightFraction).rounded())
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.26)
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(dismissDragGesture)

                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: proxy.size.width, height: cardHeight)
                .background(Color(.systemBackground))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 22,
                        style: .continuous
                    )
                )
                .shadow(color: Color.black.opacity(0.18), radius: 16, y: -4)
                .offset(y: max(0, dragOffset))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.detail.splitSheet")
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 90 || value.predictedEndTranslation.height > 160 {
                    onDismiss()
                } else {
                    withAnimation(.spring(duration: 0.22)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

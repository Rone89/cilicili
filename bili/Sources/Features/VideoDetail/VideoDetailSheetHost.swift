import SwiftUI

private struct VideoDetailSheetHostModifier: ViewModifier {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    /// 字幕选轨弹窗用本地 @State 驱动：ViewModel 的 @Published 直接绑定
    /// 在每次 body 重建时都会生成新 Binding，sheet 不会呈现。
    @State private var isShowingSubtitleSelection = false
    let sheetState: VideoDetailSheetState
    let sheetActions: VideoDetailSheetActions
    let submitReply: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetRouteBinding) { route in
                switch route {
                case .commentThread(let presentation):
                    let comment = presentation.rootComment
                    if let replyID = presentation.secondaryID,
                       let reply = viewModel.replies(for: comment).first(where: { $0.id == replyID }) {
                        CommentDialogSheet(
                            rootComment: comment,
                            focusReply: reply,
                            store: viewModel.commentThreadRenderStore,
                            loadDialog: sheetActions.replies.loadDialog,
                            reloadDialog: sheetActions.replies.reloadDialog,
                            submitReply: submitReply
                        )
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
                    } else {
                        VideoDetailReplySheetHost(
                            rootComment: comment,
                            viewModel: viewModel,
                            initialReplyID: nil,
                            actions: sheetActions.replies,
                            submitReply: submitReply
                        )
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
                case .moreControls(let presentation):
                    SurfaceOnlyMoreControlsSheet(
                        detailViewModel: viewModel,
                        viewModel: presentation.playerViewModel,
                        qualityStore: viewModel.playbackRenderStore.qualityControlStore,
                        selectPlayVariant: { viewModel.selectPlayVariant($0) },
                        onToggleDanmaku: { viewModel.toggleDanmaku() },
                        close: { sheetRouteBinding.wrappedValue = nil }
                    )
                }
            }
            .sheet(isPresented: sheetState.isShowingFavoriteFolders) {
                VideoDetailFavoriteFolderSheetHost(
                    viewModel: viewModel,
                    actions: sheetActions.favoriteFolders
                )
            }
            .sheet(isPresented: sheetState.isShowingCoinPicker) {
                VideoDetailCoinSheetHost(viewModel: viewModel)
            }
            .sheet(isPresented: sheetState.isShowingDanmakuSettings) {
                VideoDetailDanmakuSettingsSheetHost(
                    viewModel: viewModel,
                    actions: sheetActions.danmaku
                )
            }
            .sheet(isPresented: sheetState.isShowingNetworkDiagnostics) {
                VideoDetailNetworkDiagnosticsSheetHost(
                    viewModel: viewModel,
                    libraryStore: libraryStore
                )
            }
            .onChange(of: viewModel.isShowingSubtitleSelection) { _, isShowing in
                isShowingSubtitleSelection = isShowing
            }
            .sheet(
                isPresented: $isShowingSubtitleSelection,
                onDismiss: { viewModel.isShowingSubtitleSelection = false }
            ) {
                VideoDetailSubtitleSelectionSheet(
                    store: viewModel.subtitleRenderStore,
                    onSelect: { lan in
                        Task { await viewModel.selectSubtitleTrack(lan: lan) }
                    },
                    close: { isShowingSubtitleSelection = false }
                )
                // 与评论弹窗同款系统 sheet 外观（medium/large + 拖拽指示条）。
                .commentSheetPresentation()
            }
    }

    private var sheetRouteBinding: Binding<VideoDetailSheetRoute?> {
        Binding(
            get: { sheetState.route.wrappedValue },
            set: { route in
                let currentRoute = sheetState.route.wrappedValue
                guard currentRoute?.id != route?.id else { return }
                if let currentRoute {
                    finish(currentRoute)
                }
                sheetState.route.wrappedValue = route
            }
        )
    }

    private var videoReferer: String {
        let bvid = viewModel.detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        return bvid.isEmpty ? "https://www.bilibili.com" : "https://www.bilibili.com/video/\(bvid)"
    }

    private func finish(_ route: VideoDetailSheetRoute) {
        switch route {
        case .commentThread:
            viewModel.clearDeepLinkCommentThreadAnchor()
        case .moreControls(let presentation):
            presentation.finish()
        }
    }
}

extension View {
    func videoDetailSheets(
        viewModel: VideoDetailViewModel,
        libraryStore: LibraryStore,
        sheetState: VideoDetailSheetState,
        submitReply: @escaping (
            DynamicCommentComposerTarget,
            String,
            [DynamicCommentImage]?
        ) async throws -> Void
    ) -> some View {
        modifier(
            VideoDetailSheetHostModifier(
                viewModel: viewModel,
                libraryStore: libraryStore,
                sheetState: sheetState,
                sheetActions: VideoDetailSheetActions(viewModel: viewModel),
                submitReply: submitReply
            )
        )
    }
}

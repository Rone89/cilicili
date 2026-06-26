import SwiftUI

private struct VideoDetailSheetHostModifier: ViewModifier {
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    let sheetState: VideoDetailSheetState
    let sheetActions: VideoDetailSheetActions

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetState.replySheetComment) { comment in
                VideoDetailReplySheetHost(
                    rootComment: comment,
                    viewModel: viewModel,
                    actions: sheetActions.replies
                )
            }
            .sheet(isPresented: sheetState.isShowingFavoriteFolders) {
                VideoDetailFavoriteFolderSheetHost(
                    viewModel: viewModel,
                    actions: sheetActions.favoriteFolders
                )
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
    }
}

extension View {
    func videoDetailSheets(
        viewModel: VideoDetailViewModel,
        libraryStore: LibraryStore,
        sheetState: VideoDetailSheetState
    ) -> some View {
        modifier(
            VideoDetailSheetHostModifier(
                viewModel: viewModel,
                libraryStore: libraryStore,
                sheetState: sheetState,
                sheetActions: VideoDetailSheetActionsBuilder(viewModel: viewModel).actions
            )
        )
    }
}

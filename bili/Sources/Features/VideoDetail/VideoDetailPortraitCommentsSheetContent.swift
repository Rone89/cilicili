import SwiftUI

struct PortraitCommentsSheetContent: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let actions: PortraitCommentsSheetActions
    @Binding var replySheetComment: Comment?

    var body: some View {
        List {
            PortraitCommentsSheetSortRow(
                selectedSort: store.selectedSort,
                selectSort: actions.selectCommentSortAction
            )
            PortraitCommentsSheetCommentRows(
                store: store,
                actions: actions,
                replySheetComment: $replySheetComment
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .hiddenInlineNavigationTitle()
        .nativeTopScrollEdgeEffect()
        .portraitCommentsSheetLifecycle(actions: actions)
    }
}

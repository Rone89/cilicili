import SwiftUI

struct PortraitCommentsSheet: View {
    @ObservedObject var store: VideoDetailCommentsRenderStore
    let threadStore: VideoDetailCommentThreadRenderStore
    let maximumHeight: CGFloat
    let actions: PortraitCommentsSheetActions
    @State private var selectedDetent: PresentationDetent
    @State var replySheetComment: Comment?

    init(
        store: VideoDetailCommentsRenderStore,
        threadStore: VideoDetailCommentThreadRenderStore,
        maximumHeight: CGFloat,
        actions: PortraitCommentsSheetActions
    ) {
        self.store = store
        self.threadStore = threadStore
        self.maximumHeight = maximumHeight
        self.actions = actions
        _selectedDetent = State(initialValue: .height(maximumHeight))
    }

    var body: some View {
        NavigationStack {
            PortraitCommentsSheetContent(
                store: store,
                actions: actions,
                replySheetComment: $replySheetComment
            )
        }
        .presentationDetents([.height(maximumHeight)], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .sheet(item: $replySheetComment) { comment in
            PortraitCommentsReplySheet(
                comment: comment,
                store: threadStore,
                actions: actions.replies
            )
        }
    }
}

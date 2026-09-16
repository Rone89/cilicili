import SwiftUI

struct CommentDialogLoadedContent: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset
    let items: [VideoDetailCommentDialogDisplayItem]
    let focusReplyID: Int
    let footerFailureMessage: String?
    let retryDialog: () -> Void

    var body: some View {
        let horizontalPadding = standardHorizontalInset

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                CommentDialogRow(
                    item: item,
                    isFocused: item.id == focusReplyID
                )
                .padding(.horizontal, horizontalPadding)
                .id(item.id)

                Divider()
                    .padding(.leading, 66)
            }

            if let footerFailureMessage {
                CommentDialogErrorContent(message: footerFailureMessage, retry: retryDialog)
            }
        }
    }
}

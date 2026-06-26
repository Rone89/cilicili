import SwiftUI

struct DynamicCommentRow: View {
    let item: DynamicCommentRowItem
    let showReplies: () -> Void

    private var comment: Comment {
        item.comment
    }

    private var display: DynamicCommentRowDisplayModel {
        item.display
    }

    init(item: DynamicCommentRowItem, showReplies: @escaping () -> Void) {
        self.item = item
        self.showReplies = showReplies
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DynamicCommentAvatar(urlString: display.avatarURLString, size: 38)

            DynamicCommentRowContent(comment: comment, display: display, showReplies: showReplies)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 10)
    }
}

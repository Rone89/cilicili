import SwiftUI

struct VideoDetailToolbarCommentAction: View {
    let onComment: () -> Void

    var body: some View {
        Button(action: onComment) {
            Image(systemName: "square.and.pencil")
                .frame(width: 38, height: 38)
        }
        .accessibilityLabel("发表评论")
        .accessibilityIdentifier("video.detail.toolbar-comment")
        .tint(.primary)
    }
}

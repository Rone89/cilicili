import SwiftUI

struct VideoDetailToolbarCommentAction: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let onComment: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if libraryStore.accountLibraryManagementExperimentEnabled {
                Button(action: onComment) {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("发表评论")
                .accessibilityIdentifier("video.detail.toolbar-comment")
            } else {
                Menu {
                    Button(action: onComment) { Label("评论", systemImage: "square.and.pencil") }
                    Button(action: onRefresh) { Label("刷新评论区", systemImage: "arrow.clockwise") }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("更多评论操作")
                .accessibilityIdentifier("video.detail.toolbar-comment-more")
            }
        }
        .tint(.primary)
    }
}

import SwiftUI

struct CommentDialogEmptyContent: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset

    var body: some View {
        let horizontalPadding = standardHorizontalInset

        EmptyStateView(
            title: "暂无对话",
            systemImage: "text.bubble",
            message: "暂时没有找到这条回复的上下文。"
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 16)
    }
}

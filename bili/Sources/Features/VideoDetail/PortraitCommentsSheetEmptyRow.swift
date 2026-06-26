import SwiftUI

struct PortraitCommentsSheetEmptyRow: View {
    var body: some View {
        EmptyStateView(
            title: "暂无评论",
            systemImage: "bubble.left",
            message: "这里还没有可展示的评论。"
        )
        .padding(.vertical, 28)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

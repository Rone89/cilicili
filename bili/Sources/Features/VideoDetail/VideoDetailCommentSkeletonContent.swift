import SwiftUI

struct CommentsSkeletonContent: View {
    var rowCount = 4
    let horizontalPadding: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                CommentSkeletonRow()
                    .padding(.horizontal, horizontalPadding)

                Divider()
                    .padding(.leading, horizontalPadding + 48)
            }
        }
        .accessibilityLabel("正在加载评论")
    }
}

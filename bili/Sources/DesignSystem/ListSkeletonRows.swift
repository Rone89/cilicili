import SwiftUI

struct CommentLoadingSkeletonList: View {
    var count: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                CommentLoadingSkeletonRow()
                    .padding(.vertical, 12)

                if index != count - 1 {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .accessibilityLabel("正在加载评论")
    }
}

struct CommentLoadingSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonBlock(width: 40, height: 40, shape: .circle)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: 104, height: 13, shape: .capsule)
                SkeletonBlock(height: 14, shape: .rounded(5))
                SkeletonBlock(width: 230, height: 14, shape: .rounded(5))

                HStack(spacing: 12) {
                    SkeletonBlock(width: 52, height: 10, shape: .capsule)
                    SkeletonBlock(width: 38, height: 10, shape: .capsule)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchResultSkeletonRow: View {
    var body: some View {
        VideoCompactListPlaceholderRow(
            coverSize: CGSize(width: 118, height: 66),
            fill: Color(.tertiarySystemFill),
            cornerRadius: 10,
            titleMinHeight: 36,
            authorStyle: .icon("person.crop.circle"),
            metadataStyle: .search
        )
        .accessibilityLabel("正在加载搜索结果")
    }
}

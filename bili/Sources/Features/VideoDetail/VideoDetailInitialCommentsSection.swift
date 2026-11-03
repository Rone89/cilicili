import SwiftUI

struct InitialCommentsSection: View {
    @Environment(\.videoDetailStandardHorizontalInset) private var standardHorizontalInset

    private var horizontalPadding: CGFloat {
        standardHorizontalInset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("评论")
                    .font(.headline)

                Spacer()

                Picker("评论排序", selection: .constant(CommentSort.hot)) {
                    ForEach(CommentSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 124)
                .controlSize(.small)
            }
            .padding(.horizontal, horizontalPadding)

            CommentsSkeletonContent(horizontalPadding: horizontalPadding)
        }
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct InitialCommentsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("评论")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Text("最热")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.14))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                    Text("最新")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, CommentSectionStyle.plain.horizontalPadding)

            CommentsSkeletonContent(rowCount: 2, horizontalPadding: CommentSectionStyle.plain.horizontalPadding)
        }
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct CommentReplyPreviewContainer<Content: View>: View {
    let replyCount: Int
    let showsPreview: Bool
    let content: Content

    init(replyCount: Int, showsPreview: Bool, @ViewBuilder content: () -> Content) {
        self.replyCount = replyCount
        self.showsPreview = showsPreview
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsPreview {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.pink.opacity(0.42))
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Label("\(replyCount) 条回复", systemImage: "bubble.left.and.bubble.right")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.pink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
